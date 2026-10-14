import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/router/app_router.dart';
import '../../config/theme/app_colors.dart';
import '../../services/image_service.dart';
import '../../services/marketing_service.dart';

class MarketingDashboard extends StatefulWidget {
  const MarketingDashboard({super.key});

  @override
  State<MarketingDashboard> createState() => _MarketingDashboardState();
}

class _MarketingDashboardState extends State<MarketingDashboard> {
  final _service = MarketingService(Supabase.instance.client);
  final _imageService = ImageService();
  final _searchController = TextEditingController();

  bool _loading = true;
  int _tabIndex = 0;
  String _statusFilter = 'all';
  String _query = '';
  Map<String, dynamic>? _staffProfile;
  Map<String, dynamic> _settings = const {};
  List<Map<String, dynamic>> _requests = const [];
  List<Map<String, dynamic>> _events = const [];
  List<Map<String, dynamic>> _campaigns = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final staff = await _service.fetchCurrentStaffProfile();
      final requests = await _service.fetchMarketingRequests(
        status: _statusFilter,
        query: _query,
      );
      final events = await _service.fetchPublishedEvents();
      final campaigns = await _service.fetchClientCampaignCenter(limit: 50);
      final settings = await _service.fetchMarketingSettings();
      if (!mounted) return;
      setState(() {
        _staffProfile = staff;
        _settings = settings;
        _requests = requests;
        _events = events;
        _campaigns = campaigns;
      });
    } catch (error) {
      if (!mounted) return;
      _showSnack('Nao foi possivel carregar Marketing: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.softBackground,
      appBar: AppBar(
        title: const Text('DeliGo Marketing & Publicidade'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: IndexedStack(
                  index: _tabIndex,
                  children: [
                    _eventsPendingTab(),
                    _eventsPublishedTab(),
                    _advertisingTab(),
                    _sponsorshipsTab(),
                    _pushAdsTab(),
                    _couponsTab(),
                    _statisticsTab(),
                    _profileTab(),
                  ],
                ),
              ),
      ),
      floatingActionButton: _tabIndex == 2
          ? FloatingActionButton.extended(
              onPressed: _showCreateCampaignDialog,
              backgroundColor: AppColors.primaryRed,
              icon: const Icon(Icons.add),
              label: const Text('Criar campanha'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (index) => setState(() => _tabIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.pending_actions_outlined),
            selectedIcon: Icon(Icons.pending_actions),
            label: 'Pendentes',
          ),
          NavigationDestination(
            icon: Icon(Icons.event_available_outlined),
            selectedIcon: Icon(Icons.event_available),
            label: 'Publicados',
          ),
          NavigationDestination(
            icon: Icon(Icons.campaign_outlined),
            selectedIcon: Icon(Icons.campaign),
            label: 'Publicidade',
          ),
          NavigationDestination(
            icon: Icon(Icons.workspace_premium_outlined),
            selectedIcon: Icon(Icons.workspace_premium),
            label: 'Patroc.',
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications_active_outlined),
            selectedIcon: Icon(Icons.notifications_active),
            label: 'Firebase',
          ),
          NavigationDestination(
            icon: Icon(Icons.confirmation_number_outlined),
            selectedIcon: Icon(Icons.confirmation_number),
            label: 'Cupons',
          ),
          NavigationDestination(
            icon: Icon(Icons.query_stats_outlined),
            selectedIcon: Icon(Icons.query_stats),
            label: 'Estat.',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }

  Widget _dashboardTab() {
    final pending = _requests
        .where(
          (item) => item['status'] == 'pending' || item['status'] == 'received',
        )
        .length;
    final review = _requests
        .where((item) => item['status'] == 'ready_for_restaurant_review')
        .length;
    final published = _events
        .where((item) => item['status'] == 'published')
        .length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _heroCard(),
        const SizedBox(height: 12),
        _metricGrid([
          _MarketingMetric(
            Icons.assignment_late_outlined,
            'Pedidos novos',
            pending,
          ),
          _MarketingMetric(Icons.rate_review_outlined, 'A rever', review),
          _MarketingMetric(
            Icons.rocket_launch_outlined,
            'Publicados',
            published,
          ),
          _MarketingMetric(
            Icons.confirmation_number_outlined,
            'Com bilhetes',
            _events.where((item) => item['sells_tickets'] == true).length,
          ),
        ]),
        const SizedBox(height: 16),
        _sectionTitle('Fila recente'),
        if (_requests.isEmpty)
          _emptyCard('Ainda nao existem pedidos de marketing.')
        else
          ..._requests.take(5).map(_requestCard),
        const SizedBox(height: 16),
        _sectionTitle('Centro de Campanhas'),
        _campaignCreateCard(),
        const SizedBox(height: 8),
        if (_campaigns.isEmpty)
          _emptyCard('Nenhuma campanha publicada no app cliente.')
        else
          ..._campaigns.take(5).map(_campaignCard),
      ],
    );
  }

  Widget _eventsPendingTab() {
    const reviewStatuses = {
      'received',
      'in_design',
      'ready_for_restaurant_review',
    };
    final pending = _requests
        .where((item) => reviewStatuses.contains(item['status']?.toString()))
        .toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _heroCard(),
        const SizedBox(height: 12),
        _sectionTitle('Eventos Pendentes'),
        if (pending.isEmpty)
          _emptyCard('Nao ha eventos pendentes neste momento.')
        else
          ...pending.map(_requestCard),
      ],
    );
  }

  Widget _eventsPublishedTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionTitle('Eventos e Historico'),
        if (_events.isEmpty)
          _emptyCard('Nenhum evento publicado ainda.')
        else
          ..._events.map(_eventCard),
      ],
    );
  }

  Widget _advertisingTab() {
    final ads = _campaigns.where((item) {
      final type =
          item['type']?.toString() ?? item['campaign_type']?.toString();
      return type == 'ad' ||
          type == 'deli' ||
          type == 'video' ||
          type == 'event' ||
          type == 'ticket' ||
          item['placement'] == 'home_banner' ||
          item['placement'] == 'splash_screen' ||
          item['placement'] == 'video_ad';
    }).toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionTitle('Publicidade'),
        _campaignObjectiveGrid(),
        const SizedBox(height: 12),
        _marketingLimitsWrap(),
        const SizedBox(height: 16),
        if (ads.isEmpty)
          _emptyCard('Nenhuma publicidade ativa ainda.')
        else
          ...ads.map(_campaignCard),
      ],
    );
  }

  Widget _sponsorshipsTab() {
    final sponsored = _campaigns
        .where(
          (item) =>
              item['type'] == 'sponsor' ||
              item['campaign_type'] == 'sponsor' ||
              item['placement'] == 'featured_restaurant' ||
              (item['priority'] as num? ?? 0) >= 10,
        )
        .toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionTitle('Patrocinios'),
        _infoCard(
          Icons.workspace_premium_outlined,
          'Tipos premium',
          'Evento, restaurante, produto, categoria e banner patrocinado.',
        ),
        const SizedBox(height: 12),
        if (sponsored.isEmpty)
          _emptyCard('Nenhum patrocinio configurado.')
        else
          ...sponsored.map(_campaignCard),
      ],
    );
  }

  Widget _pushAdsTab() {
    final pushAds = _campaigns
        .where(
          (item) =>
              item['type'] == 'push' ||
              item['campaign_type'] == 'push' ||
              item['placement'] == 'push',
        )
        .toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionTitle('Firebase Push Ads'),
        _infoCard(
          Icons.notifications_active_outlined,
          'Push segmentado',
          'Campanhas, cupons, eventos e anuncios urgentes por cidade/interesses.',
        ),
        const SizedBox(height: 12),
        if (pushAds.isEmpty)
          _emptyCard('Nenhum Push Ad criado ainda.')
        else
          ...pushAds.map(_campaignCard),
      ],
    );
  }

  Widget _couponsTab() {
    final coupons = _campaigns
        .where((item) => item['coupon_code']?.toString().isNotEmpty == true)
        .toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionTitle('Cupons'),
        if (coupons.isEmpty)
          _emptyCard('Nenhum cupom publicado.')
        else
          ...coupons.map(_campaignCard),
      ],
    );
  }

  Widget _statisticsTab() {
    final impressions = _campaigns.fold<int>(
      0,
      (sum, item) => sum + ((item['views'] as num?)?.toInt() ?? 0),
    );
    final clicks = _campaigns.fold<int>(
      0,
      (sum, item) => sum + ((item['clicks'] as num?)?.toInt() ?? 0),
    );
    final conversions = _campaigns.fold<int>(
      0,
      (sum, item) => sum + ((item['conversions'] as num?)?.toInt() ?? 0),
    );
    final revenue = _campaigns.fold<double>(
      0,
      (sum, item) =>
          sum + ((item['revenue_generated'] as num?)?.toDouble() ?? 0),
    );
    final ctr = impressions == 0 ? 0 : (clicks / impressions) * 100;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionTitle('Estatisticas'),
        _metricGrid([
          _MarketingMetric(
            Icons.visibility_outlined,
            'Impressoes',
            impressions,
          ),
          _MarketingMetric(Icons.touch_app_outlined, 'Cliques', clicks),
          _MarketingMetric(
            Icons.shopping_cart_checkout,
            'Conversoes',
            conversions,
          ),
          _MarketingMetric(
            Icons.percent,
            'CTR ${ctr.toStringAsFixed(1)}%',
            clicks,
          ),
        ]),
        const SizedBox(height: 12),
        _infoCard(
          Icons.payments_outlined,
          'Receita gerada',
          '${revenue.toStringAsFixed(2)} MZN em campanhas acompanhadas.',
        ),
        const SizedBox(height: 12),
        _marketingLimitsWrap(),
      ],
    );
  }

  Widget _requestsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _filters(),
        const SizedBox(height: 12),
        if (_requests.isEmpty)
          _emptyCard('Nenhum pedido encontrado.')
        else
          ..._requests.map(_requestCard),
      ],
    );
  }

  Widget _eventsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionTitle('Eventos publicados na DeliGo'),
        if (_events.isEmpty)
          _emptyCard('Nenhum evento publicado ainda.')
        else
          ..._events.map(_eventCard),
      ],
    );
  }

  Widget _assetsTab() {
    final assets = _requests.expand((request) sync* {
      final posterUrl = request['poster_url']?.toString().trim() ?? '';
      final bannerUrl = request['banner_url']?.toString().trim() ?? '';
      if (posterUrl.isNotEmpty) {
        yield {'request': request, 'type': 'Cartaz', 'url': posterUrl};
      }
      if (bannerUrl.isNotEmpty) {
        yield {'request': request, 'type': 'Banner', 'url': bannerUrl};
      }
    }).toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionTitle('Producoes criativas'),
        if (assets.isEmpty)
          _emptyCard('Ainda nao existem imagens publicadas.')
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: assets.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.82,
            ),
            itemBuilder: (context, index) => _assetImageCard(assets[index]),
          ),
      ],
    );
  }

  Widget _profileTab() {
    final profile = _staffProfile ?? const <String, dynamic>{};
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _profileRow('Nome', profile['full_name']?.toString() ?? '-'),
                _profileRow('Telefone', profile['phone']?.toString() ?? '-'),
                _profileRow('Cargo', 'Marketing e Publicidade'),
                _profileRow(
                  'Estado',
                  profile['staff_active'] == false ? 'Inativo' : 'Ativo',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _logout,
          icon: const Icon(Icons.logout),
          label: const Text('Terminar sessao'),
        ),
      ],
    );
  }

  Widget _heroCard() {
    final name = _staffProfile?['full_name']?.toString() ?? 'Equipa Marketing';
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            const CircleAvatar(
              radius: 28,
              child: Icon(Icons.campaign_outlined),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  const Text(
                    'Campanhas, promocoes, eventos e visibilidade dos restaurantes.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filters() {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Pesquisar restaurante, evento ou tipo',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
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
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _statusFilter,
              decoration: const InputDecoration(labelText: 'Estado'),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('Todos')),
                DropdownMenuItem(value: 'received', child: Text('Recebidos')),
                DropdownMenuItem(
                  value: 'in_design',
                  child: Text('Em producao'),
                ),
                DropdownMenuItem(
                  value: 'revision_requested',
                  child: Text('Em revisao'),
                ),
                DropdownMenuItem(
                  value: 'ready_for_restaurant_review',
                  child: Text('Aguardando restaurante'),
                ),
                DropdownMenuItem(value: 'published', child: Text('Publicados')),
              ],
              onChanged: (value) {
                setState(() => _statusFilter = value ?? 'all');
                _load();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _requestCard(Map<String, dynamic> request) {
    final restaurant = request['restaurants'] is Map
        ? Map<String, dynamic>.from(request['restaurants'] as Map)
        : const <String, dynamic>{};
    final status = request['status']?.toString() ?? 'pending';
    final imageUrl = request['banner_url']?.toString().trim().isNotEmpty == true
        ? request['banner_url'].toString()
        : request['poster_url']?.toString();
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openRequest(request),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 2,
              child: imageUrl?.isNotEmpty == true
                  ? Image.network(
                      imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _requestImagePlaceholder(),
                    )
                  : _requestImagePlaceholder(),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          request['event_name']?.toString() ?? 'Evento',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Chip(label: Text(_statusLabel(status))),
                    ],
                  ),
                  Text(
                    '${restaurant['name']?.toString() ?? 'Restaurante'} - ${restaurant['city']?.toString() ?? 'Cidade nao indicada'}',
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${request['event_date'] ?? '-'} as ${request['event_time'] ?? '-'}  |  Enviado ${_shortDate(request['created_at'])}',
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => _openRequest(request),
                    icon: const Icon(Icons.rate_review_outlined),
                    label: const Text('Rever'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _requestImagePlaceholder() => Container(
    color: AppColors.borderGray.withValues(alpha: 0.35),
    alignment: Alignment.center,
    child: const Icon(Icons.image_outlined, size: 46),
  );

  Widget _eventCard(Map<String, dynamic> event) {
    final sold = (event['tickets_sold'] as num?)?.toInt() ?? 0;
    final quantity = (event['ticket_quantity'] as num?)?.toInt();
    final status = event['status']?.toString() ?? 'published';
    final canCancel = status == 'published' || status == 'sold_out';
    final refunded = (event['refunded_amount'] as num?)?.toDouble() ?? 0;
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const CircleAvatar(child: Icon(Icons.event_available)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event['title']?.toString() ?? 'Evento',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        '${event['event_date'] ?? '-'} ${event['event_time'] ?? ''}',
                      ),
                    ],
                  ),
                ),
                Chip(label: Text(_statusLabel(status))),
              ],
            ),
            const SizedBox(height: 8),
            Text(event['location']?.toString() ?? 'Localizacao por confirmar'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  label: Text(
                    event['sells_tickets'] == true
                        ? 'Bilhetes $sold/${quantity ?? 0}'
                        : 'Sem bilhetes',
                  ),
                ),
                if (refunded > 0)
                  Chip(
                    label: Text(
                      'Reembolsado ${refunded.toStringAsFixed(2)} MT',
                    ),
                  ),
              ],
            ),
            if (event['cancellation_reason']?.toString().isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Motivo: ${event['cancellation_reason']}'),
              ),
            if (canCancel) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => _cancelEvent(event),
                icon: const Icon(Icons.event_busy_outlined),
                label: const Text('Cancelar e reembolsar'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _cancelEvent(Map<String, dynamic> event) async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancelar evento?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(event['title']?.toString() ?? 'Evento'),
            const SizedBox(height: 8),
            const Text(
              'Todos os bilhetes validos serao cancelados e reembolsados pela Wallet. Esta acao nao pode ser desfeita.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Motivo obrigatorio',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () {
              if (reasonController.text.trim().isEmpty) return;
              Navigator.pop(dialogContext, true);
            },
            child: const Text('Cancelar evento'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final result = await _service.cancelEventAndRefund(
        eventId: event['id'].toString(),
        reason: reasonController.text,
      );
      final count = (result['refunded_tickets'] as num?)?.toInt() ?? 0;
      final amount = (result['refunded_amount'] as num?)?.toDouble() ?? 0;
      _showSnack(
        'Evento cancelado. $count bilhete(s) e ${amount.toStringAsFixed(2)} MT reembolsados.',
        success: true,
      );
      await _load();
    } catch (error) {
      debugPrint('Erro ao cancelar evento: $error');
      _showSnack(
        'Nao foi possivel cancelar o evento. Nenhum saldo foi alterado.',
      );
    }
  }

  Widget _assetImageCard(Map<String, dynamic> asset) {
    final request = Map<String, dynamic>.from(asset['request'] as Map);
    final url = asset['url']?.toString() ?? '';
    final type = asset['type']?.toString() ?? 'Imagem';
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              color: AppColors.borderGray.withValues(alpha: 0.35),
              child: Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    const Center(child: Icon(Icons.broken_image_outlined)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(type, style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(
                  request['event_name']?.toString() ?? 'Material',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _campaignCreateCard() {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(child: Icon(Icons.auto_awesome)),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Criar campanha',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Ofertas, eventos, novidades, banners e descoberta inteligente.',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _showCreateCampaignDialog,
              icon: const Icon(Icons.add),
              label: const Text('Nova campanha'),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: const [
                Chip(label: Text('Ofertas')),
                Chip(label: Text('Eventos')),
                Chip(label: Text('Novidades')),
                Chip(label: Text('Descoberta')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _campaignObjectiveGrid() {
    final objectives = [
      (
        Icons.event_available_outlined,
        'Promover Evento',
        'Seleciona um evento ja publicado.',
      ),
      (
        Icons.storefront_outlined,
        'Promover Restaurante',
        'Destaque para parceiro DeliGo.',
      ),
      (
        Icons.inventory_2_outlined,
        'Promover Produto',
        'Produto, prato ou oferta especifica.',
      ),
      (
        Icons.business_center_outlined,
        'Novo Anuncio',
        'Marca externa, link, WhatsApp ou telefone.',
      ),
      (
        Icons.local_fire_department_outlined,
        'Campanha DeliGo',
        'Wallet, frete gratis, datas especiais.',
      ),
      (
        Icons.video_collection_outlined,
        'Video Ads',
        'Splash ou video curto monetizavel.',
      ),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: objectives.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.8,
      ),
      itemBuilder: (context, index) {
        final item = objectives[index];
        return Card(
          elevation: 0,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _showCreateCampaignDialog,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: AppColors.primaryRed.withValues(
                      alpha: 0.10,
                    ),
                    child: Icon(item.$1, color: AppColors.primaryRed),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          item.$2,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          item.$3,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.neutralGray,
                            fontSize: 12,
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
      },
    );
  }

  Widget _marketingLimitsWrap() {
    final values = [
      ('Banners', _settingInt('home_banner_limit', 5)),
      ('Patrocinados', _settingInt('sponsored_limit', 10)),
      ('Destaques', _settingInt('featured_limit', 20)),
      ('Videos/sessao', _settingInt('video_limit', 1)),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: values
          .map(
            (item) => Chip(
              avatar: const Icon(Icons.tune, size: 16),
              label: Text('${item.$1}: ${item.$2}'),
              visualDensity: VisualDensity.compact,
            ),
          )
          .toList(),
    );
  }

  int _settingInt(String key, int fallback) {
    return (_settings[key] as num?)?.toInt() ?? fallback;
  }

  Widget _infoCard(IconData icon, String title, String body) {
    return Card(
      elevation: 0,
      child: ListTile(
        leading: CircleAvatar(child: Icon(icon)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(body),
      ),
    );
  }

  Widget _campaignCard(Map<String, dynamic> campaign) {
    final restaurant = campaign['restaurants'] is Map
        ? Map<String, dynamic>.from(campaign['restaurants'] as Map)
        : const <String, dynamic>{};
    final restaurantName = restaurant['name']?.toString().trim() ?? '';
    final coupon = campaign['coupon_code']?.toString().trim() ?? '';
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CircleAvatar(child: Icon(Icons.campaign_outlined)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    campaign['title']?.toString() ?? 'Campanha',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    campaign['subtitle']?.toString().trim().isNotEmpty == true
                        ? campaign['subtitle'].toString()
                        : campaign['description']?.toString() ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text(
                          _placementLabel(campaign['placement']?.toString()),
                        ),
                      ),
                      Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text(
                          _campaignTypeLabel(
                            campaign['campaign_type']?.toString(),
                          ),
                        ),
                      ),
                      if (restaurantName.isNotEmpty)
                        Chip(
                          visualDensity: VisualDensity.compact,
                          avatar: const Icon(
                            Icons.storefront_outlined,
                            size: 16,
                          ),
                          label: Text(restaurantName),
                        ),
                      if (coupon.isNotEmpty)
                        Chip(
                          visualDensity: VisualDensity.compact,
                          avatar: const Icon(
                            Icons.confirmation_number_outlined,
                            size: 16,
                          ),
                          label: Text(coupon),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCreateCampaignDialog() async {
    final titleController = TextEditingController();
    final subtitleController = TextEditingController();
    final descriptionController = TextEditingController();
    final couponController = TextEditingController();
    final discountController = TextEditingController();
    final actionController = TextEditingController(text: 'Ver agora');
    final externalUrlController = TextEditingController();
    final whatsappController = TextEditingController();
    final phoneController = TextEditingController();
    final videoUrlController = TextEditingController();
    final companyController = TextEditingController();
    final budgetController = TextEditingController();
    final citiesController = TextEditingController();
    final neighborhoodsController = TextEditingController();
    String objective = 'promote_event';
    String placement = 'campaign_center';
    String campaignType = 'event';
    String type = 'event';
    String discountType = 'percent';
    String actionType = 'auto';
    bool newClients = false;
    bool frequentClients = false;
    int priority = 0;
    Map<String, dynamic>? selectedRestaurant;
    Map<String, dynamic>? selectedEvent;
    String? campaignImageUrl;
    String? companyLogoUrl;
    String? campaignVideoUrl;
    DateTime startsAt = DateTime.now();
    DateTime endsAt = DateTime.now().add(const Duration(days: 7));
    RangeValues hourRange = const RangeValues(8, 22);
    final weekdays = <int>{1, 2, 3, 4, 5, 6, 7};
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Nova campanha'),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _formSectionTitle('Objetivo da campanha'),
                  DropdownButtonFormField<String>(
                    value: objective,
                    decoration: const InputDecoration(labelText: 'Objetivo'),
                    items: const [
                      DropdownMenuItem(
                        value: 'promote_event',
                        child: Text('Promover evento'),
                      ),
                      DropdownMenuItem(
                        value: 'promote_restaurant',
                        child: Text('Promover restaurante'),
                      ),
                      DropdownMenuItem(
                        value: 'promote_product',
                        child: Text('Promover produto'),
                      ),
                      DropdownMenuItem(
                        value: 'external_ad',
                        child: Text('Novo anuncio externo'),
                      ),
                      DropdownMenuItem(
                        value: 'deli_campaign',
                        child: Text('Campanha DeliGo'),
                      ),
                      DropdownMenuItem(
                        value: 'video_ad',
                        child: Text('Video Ads / Splash'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() {
                        objective = value;
                        switch (value) {
                          case 'promote_event':
                            type = 'event';
                            campaignType = 'event';
                            placement = 'events_today';
                            actionType = 'open_event';
                            break;
                          case 'promote_restaurant':
                            type = 'sponsor';
                            campaignType = 'featured_restaurant';
                            placement = 'featured_restaurant';
                            actionType = 'open_restaurant';
                            break;
                          case 'promote_product':
                            type = 'sponsor';
                            campaignType = 'promotion';
                            placement = 'feed';
                            actionType = 'open_product';
                            break;
                          case 'external_ad':
                            type = 'ad';
                            campaignType = 'ad';
                            placement = 'home_banner';
                            actionType = 'external_link';
                            break;
                          case 'deli_campaign':
                            type = 'deli';
                            campaignType = 'news';
                            placement = 'campaign_center';
                            actionType = 'custom_page';
                            break;
                          case 'video_ad':
                            type = 'video';
                            campaignType = 'video';
                            placement = 'video_ad';
                            actionType = 'custom_page';
                            break;
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  _formSectionTitle('Conteudo'),
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(labelText: 'Titulo'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: subtitleController,
                    decoration: const InputDecoration(labelText: 'Subtitulo'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descriptionController,
                    decoration: const InputDecoration(labelText: 'Descricao'),
                    minLines: 2,
                    maxLines: 4,
                  ),
                  const SizedBox(height: 12),
                  _horizontalChoice<String>(
                    label: 'Espaco no app',
                    value: placement,
                    values: const [
                      'campaign_center',
                      'home_banner',
                      'daily_offer',
                      'featured_restaurant',
                      'events_today',
                      'tickets',
                      'smart_discovery',
                      'seasonal',
                      'secondary_banner',
                      'feed',
                      'category',
                      'splash_screen',
                      'video_ad',
                      'push',
                    ],
                    labelBuilder: (value) => _placementLabel(value),
                    onChanged: (value) =>
                        setDialogState(() => placement = value),
                  ),
                  const SizedBox(height: 12),
                  _horizontalChoice<String>(
                    label: 'Tipo',
                    value: campaignType,
                    values: const [
                      'coupon',
                      'promotion',
                      'daily_offer',
                      'featured_restaurant',
                      'event',
                      'ticket',
                      'banner',
                      'news',
                      'smart_discovery',
                      'ad',
                      'deli',
                      'video',
                      'sponsor',
                      'push',
                    ],
                    labelBuilder: (value) => _campaignTypeLabel(value),
                    onChanged: (value) => setDialogState(() {
                      campaignType = value;
                      type = value;
                    }),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: companyController,
                    decoration: const InputDecoration(
                      labelText: 'Empresa / anunciante',
                      hintText: 'Coca-Cola, Vodacom, Heineken...',
                    ),
                  ),
                  const SizedBox(height: 12),
                  _formSectionTitle('Restaurante e media'),
                  _uploadTile(
                    title: 'Logo da empresa',
                    value: companyLogoUrl,
                    onUpload: () async {
                      final uploaded = await _uploadMarketingImage('logos');
                      if (uploaded != null) {
                        setDialogState(() => companyLogoUrl = uploaded);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  _selectionTile(
                    icon: Icons.storefront_outlined,
                    title: 'Restaurante',
                    value:
                        selectedRestaurant?['name']?.toString() ??
                        'Pesquisar restaurante por nome',
                    onTap: () async {
                      final restaurant = await _pickRestaurant();
                      if (restaurant != null) {
                        setDialogState(() => selectedRestaurant = restaurant);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  _selectionTile(
                    icon: Icons.event_outlined,
                    title: 'Evento relacionado',
                    value:
                        selectedEvent?['title']?.toString() ??
                        'Selecionar evento publicado',
                    onTap: () async {
                      final event = await _pickEvent();
                      if (event != null) {
                        setDialogState(() => selectedEvent = event);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: couponController,
                    decoration: const InputDecoration(
                      labelText: 'Codigo promocional',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: discountType,
                    decoration: const InputDecoration(
                      labelText: 'Tipo de desconto',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'percent',
                        child: Text('Percentual'),
                      ),
                      DropdownMenuItem(
                        value: 'fixed_amount',
                        child: Text('Valor fixo'),
                      ),
                      DropdownMenuItem(
                        value: 'free_delivery',
                        child: Text('Entrega gratis'),
                      ),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => discountType = value ?? 'percent'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: discountController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Valor do desconto',
                    ),
                  ),
                  const SizedBox(height: 12),
                  _uploadTile(
                    title: 'Imagem ou banner',
                    value: campaignImageUrl,
                    onUpload: () async {
                      final uploaded = await _uploadMarketingImage('campaigns');
                      if (uploaded != null) {
                        setDialogState(() => campaignImageUrl = uploaded);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  _uploadTile(
                    title: 'Video curto',
                    value: campaignVideoUrl,
                    onUpload: () async {
                      final uploaded = await _uploadMarketingVideo('videos');
                      if (uploaded != null) {
                        setDialogState(() {
                          campaignVideoUrl = uploaded;
                          videoUrlController.text = uploaded;
                          if (placement == 'campaign_center') {
                            placement = 'video_ad';
                          }
                          type = 'video';
                          campaignType = 'video';
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Videos devem ter ate 10 segundos. No app cliente aparece com botao Saltar.',
                    style: TextStyle(
                      color: AppColors.neutralGray,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: videoUrlController,
                    decoration: const InputDecoration(
                      labelText: 'Video URL',
                      hintText: 'Opcional para Video Ads ou Splash',
                    ),
                  ),
                  const SizedBox(height: 12),
                  _formSectionTitle('Periodo e regras'),
                  Row(
                    children: [
                      Expanded(
                        child: _dateTimeTile(
                          title: 'Inicio',
                          value: startsAt,
                          onChanged: (value) =>
                              setDialogState(() => startsAt = value),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _dateTimeTile(
                          title: 'Fim',
                          value: endsAt,
                          onChanged: (value) =>
                              setDialogState(() => endsAt = value),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _weekdaySelector(
                    selected: weekdays,
                    onChanged: (day, selected) => setDialogState(() {
                      if (selected) {
                        weekdays.add(day);
                      } else {
                        weekdays.remove(day);
                      }
                    }),
                  ),
                  const SizedBox(height: 12),
                  _hourRangeSelector(
                    value: hourRange,
                    onChanged: (value) =>
                        setDialogState(() => hourRange = value),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: actionController,
                    decoration: const InputDecoration(labelText: 'Botao'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: budgetController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Orcamento / valor pago',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: actionType,
                    decoration: const InputDecoration(
                      labelText: 'Acao ao clicar',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'auto',
                        child: Text('Automatico'),
                      ),
                      DropdownMenuItem(
                        value: 'open_event',
                        child: Text('Abrir Evento'),
                      ),
                      DropdownMenuItem(
                        value: 'open_restaurant',
                        child: Text('Abrir Restaurante'),
                      ),
                      DropdownMenuItem(
                        value: 'open_product',
                        child: Text('Abrir Produto'),
                      ),
                      DropdownMenuItem(
                        value: 'open_store',
                        child: Text('Abrir Loja'),
                      ),
                      DropdownMenuItem(
                        value: 'activate_coupon',
                        child: Text('Abrir Cupao'),
                      ),
                      DropdownMenuItem(
                        value: 'open_category',
                        child: Text('Abrir Categoria'),
                      ),
                      DropdownMenuItem(
                        value: 'open_promotion',
                        child: Text('Abrir Promocao'),
                      ),
                      DropdownMenuItem(
                        value: 'custom_page',
                        child: Text('Abrir Pagina Personalizada'),
                      ),
                      DropdownMenuItem(
                        value: 'external_link',
                        child: Text('Abrir Link Externo'),
                      ),
                      DropdownMenuItem(
                        value: 'whatsapp',
                        child: Text('Abrir WhatsApp'),
                      ),
                      DropdownMenuItem(value: 'call', child: Text('Ligar')),
                      DropdownMenuItem(
                        value: 'buy_ticket',
                        child: Text('Comprar Bilhete'),
                      ),
                      DropdownMenuItem(
                        value: 'reserve_table',
                        child: Text('Reservar Mesa'),
                      ),
                      DropdownMenuItem(
                        value: 'make_order',
                        child: Text('Fazer Pedido'),
                      ),
                      DropdownMenuItem(
                        value: 'open_location',
                        child: Text('Abrir Localizacao'),
                      ),
                      DropdownMenuItem(
                        value: 'open_company_profile',
                        child: Text('Abrir Perfil da Empresa'),
                      ),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => actionType = value ?? 'auto'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: externalUrlController,
                    decoration: const InputDecoration(
                      labelText: 'Link externo ou pagina personalizada',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: whatsappController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'WhatsApp'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Telefone'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    value: priority,
                    decoration: const InputDecoration(labelText: 'Prioridade'),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('Normal')),
                      DropdownMenuItem(value: 5, child: Text('Alta')),
                      DropdownMenuItem(value: 10, child: Text('Muito alta')),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => priority = value ?? 0),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: citiesController,
                    decoration: const InputDecoration(
                      labelText: 'Cidades alvo',
                      hintText: 'Maputo, Matola',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: neighborhoodsController,
                    decoration: const InputDecoration(
                      labelText: 'Bairros alvo',
                      hintText: 'Polana, Sommerschield',
                    ),
                  ),
                  SwitchListTile(
                    value: newClients,
                    title: const Text('Clientes novos'),
                    onChanged: (value) =>
                        setDialogState(() => newClients = value),
                  ),
                  SwitchListTile(
                    value: frequentClients,
                    title: const Text('Clientes frequentes'),
                    onChanged: (value) =>
                        setDialogState(() => frequentClients = value),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Pre-visualizar'),
            ),
          ],
        ),
      ),
    );
    if (created != true) return;
    final validationError = _validateCampaignDraft(
      title: titleController.text,
      placement: placement,
      campaignType: campaignType,
      startsAt: startsAt,
      endsAt: endsAt,
      imageUrl: campaignImageUrl,
      selectedRestaurant: selectedRestaurant,
      selectedEvent: selectedEvent,
      couponCode: couponController.text,
      actionType: actionType,
      externalUrl: externalUrlController.text,
      whatsapp: whatsappController.text,
      phone: phoneController.text,
    );
    if (validationError != null) {
      _showSnack(validationError);
      return;
    }
    final confirmed = await _showCampaignPreview(
      title: titleController.text,
      subtitle: subtitleController.text,
      description: descriptionController.text,
      placement: placement,
      campaignType: campaignType,
      imageUrl: campaignImageUrl,
      restaurantName: selectedRestaurant?['name']?.toString(),
      eventName: selectedEvent?['title']?.toString(),
      startsAt: startsAt,
      endsAt: endsAt,
      actionLabel: actionController.text,
    );
    if (confirmed != true) return;
    try {
      await _service.createCampaign(
        restaurantId: selectedRestaurant?['id']?.toString(),
        eventId: selectedEvent?['id']?.toString(),
        title: titleController.text,
        subtitle: subtitleController.text,
        description: descriptionController.text,
        placement: placement,
        campaignType: campaignType,
        type: type,
        objective: objective,
        targetType: selectedEvent != null
            ? 'event'
            : selectedRestaurant != null
            ? 'restaurant'
            : actionType == 'open_product'
            ? 'product'
            : actionType == 'external_link'
            ? 'external_link'
            : 'none',
        targetId:
            selectedEvent?['id']?.toString() ??
            selectedRestaurant?['id']?.toString(),
        couponCode: couponController.text,
        discountType: couponController.text.trim().isEmpty
            ? null
            : discountType,
        discountValue: double.tryParse(
          discountController.text.replaceAll(',', '.'),
        ),
        startsAt: startsAt.toUtc().toIso8601String(),
        endsAt: endsAt.toUtc().toIso8601String(),
        imageUrl: campaignImageUrl,
        videoUrl: campaignVideoUrl ?? videoUrlController.text,
        actionLabel: actionController.text,
        priority: priority,
        budget:
            double.tryParse(budgetController.text.replaceAll(',', '.')) ?? 0,
        metadata: {
          'objective': objective,
          'type': type,
          'company_name': companyController.text.trim(),
          'company_logo_url': companyLogoUrl,
          'video_url': campaignVideoUrl ?? videoUrlController.text.trim(),
          'splash_skip_seconds': 3,
          'max_duration_seconds': 10,
          'cities': citiesController.text
              .split(',')
              .map((item) => item.trim().toLowerCase())
              .where((item) => item.isNotEmpty)
              .toList(),
          'neighborhoods': neighborhoodsController.text
              .split(',')
              .map((item) => item.trim().toLowerCase())
              .where((item) => item.isNotEmpty)
              .toList(),
          'hours': List<int>.generate(
            hourRange.end.round() - hourRange.start.round() + 1,
            (index) => hourRange.start.round() + index,
          ),
          'weekdays': weekdays.toList()..sort(),
          'new_clients': newClients,
          'frequent_clients': frequentClients,
          'action_type': actionType,
          'external_url': externalUrlController.text.trim(),
          'whatsapp': whatsappController.text.trim(),
          'phone': phoneController.text.trim(),
        },
      );
      _showSnack('Campanha publicada no DeliGo App.', success: true);
      await _load();
    } catch (error) {
      _showSnack('Erro ao publicar campanha: $error');
    }
  }

  Future<void> _openRequest(Map<String, dynamic> request) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => _eventReviewPage(request)));
  }

  Widget _eventReviewPage(Map<String, dynamic> request) {
    final restaurant = request['restaurants'] is Map
        ? Map<String, dynamic>.from(request['restaurants'] as Map)
        : const <String, dynamic>{};
    final banner = request['banner_url']?.toString().trim().isNotEmpty == true
        ? request['banner_url'].toString()
        : request['poster_url']?.toString();
    final tickets = request['ticket_options'] is List
        ? (request['ticket_options'] as List)
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList()
        : const <Map<String, dynamic>>[];

    return Builder(
      builder: (pageContext) => Scaffold(
        appBar: AppBar(title: const Text('Rever evento')),
        body: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            AspectRatio(
              aspectRatio: 2,
              child: banner?.isNotEmpty == true
                  ? Image.network(
                      banner!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _requestImagePlaceholder(),
                    )
                  : _requestImagePlaceholder(),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    request['event_name']?.toString() ?? 'Evento',
                    style: Theme.of(pageContext).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    restaurant['name']?.toString() ?? 'Restaurante',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 18),
                  _reviewSection(
                    'Como o cliente vera',
                    request['description']?.toString() ?? 'Sem descricao.',
                  ),
                  _reviewInfo(
                    Icons.calendar_today_outlined,
                    'Data',
                    request['event_date']?.toString() ?? '-',
                  ),
                  _reviewInfo(
                    Icons.schedule_outlined,
                    'Horario',
                    '${request['event_time'] ?? '-'} - ${request['event_end_time'] ?? '-'}',
                  ),
                  _reviewInfo(
                    Icons.location_on_outlined,
                    'Local e mapa',
                    request['location']?.toString() ?? '-',
                  ),
                  _reviewInfo(
                    Icons.storefront_outlined,
                    'Organizador',
                    '${restaurant['name'] ?? '-'} | ${restaurant['phone'] ?? '-'}',
                  ),
                  _reviewInfo(
                    Icons.category_outlined,
                    'Categoria',
                    '${request['event_category'] ?? '-'} | ${request['event_type_detail'] ?? '-'}',
                  ),
                  if (request['max_capacity'] != null)
                    _reviewInfo(
                      Icons.groups_outlined,
                      'Capacidade',
                      '${request['max_capacity']} pessoas',
                    ),
                  const SizedBox(height: 8),
                  _reviewSection(
                    'Tipos de bilhete',
                    tickets.isEmpty
                        ? 'Este evento nao vende bilhetes.'
                        : tickets
                              .map(
                                (ticket) =>
                                    '${ticket['name'] ?? 'Bilhete'} - ${ticket['price'] ?? 0} MT - ${ticket['quantity'] ?? 0} lugares',
                              )
                              .join('\n'),
                  ),
                  _reviewSection(
                    'Regras',
                    request['rules']?.toString().trim().isNotEmpty == true
                        ? request['rules'].toString()
                        : 'Sem regras adicionais.',
                  ),
                  _reviewSection(
                    'Politica de reembolso',
                    request['refund_policy']?.toString().trim().isNotEmpty ==
                            true
                        ? request['refund_policy'].toString()
                        : 'Nao indicada.',
                  ),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      if (await _rejectEvent(request)) {
                        if (pageContext.mounted) Navigator.pop(pageContext);
                      }
                    },
                    child: const Text('Rejeitar'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      if (await _requestEventChanges(request)) {
                        if (pageContext.mounted) Navigator.pop(pageContext);
                      }
                    },
                    child: const Text('Alteracoes'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: () async {
                      if (await _approveEvent(request, restaurant)) {
                        if (pageContext.mounted) Navigator.pop(pageContext);
                      }
                    },
                    child: const Text('Aprovar'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _reviewSection(String title, String body) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text(body),
      ],
    ),
  );

  Widget _reviewInfo(IconData icon, String label, String value) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon),
    title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    subtitle: Text(value),
  );

  Future<bool> _approveEvent(
    Map<String, dynamic> request,
    Map<String, dynamic> restaurant,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Aprovar evento?'),
        content: Text(
          '${request['event_name'] ?? 'Evento'}\n${restaurant['name'] ?? 'Restaurante'}\n\nTudo correto para publicar no DeliGo App?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Aprovar evento'),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;
    try {
      await _service.approveAndPublishRequest(request['id'].toString());
      _showSnack('Evento aprovado e publicado no DeliGo App.', success: true);
      await _load();
      return true;
    } catch (error) {
      _showSnack('Nao foi possivel aprovar: $error');
      return false;
    }
  }

  Future<bool> _requestEventChanges(Map<String, dynamic> request) async {
    const options = [
      'Trocar imagem',
      'Corrigir descricao',
      'Corrigir data',
      'Corrigir precos',
      'Documento invalido',
      'Outro',
    ];
    final selected = <String>{};
    final notesController = TextEditingController();
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Solicitar alteracoes'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...options.map(
                  (option) => CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: selected.contains(option),
                    title: Text(option),
                    onChanged: (value) => setDialogState(() {
                      value == true
                          ? selected.add(option)
                          : selected.remove(option);
                    }),
                  ),
                ),
                TextField(
                  controller: notesController,
                  minLines: 3,
                  maxLines: 5,
                  decoration: const InputDecoration(labelText: 'Observacoes'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, true),
              child: const Text('Enviar'),
            ),
          ],
        ),
      ),
    );
    if (submitted != true) return false;
    final reason = [
      ...selected,
      if (notesController.text.trim().isNotEmpty) notesController.text.trim(),
    ].join(': ');
    try {
      await _service.requestRevision(
        requestId: request['id'].toString(),
        notes: reason,
      );
      await _service.sendRequestMessage(
        requestId: request['id'].toString(),
        senderRole: 'marketing_agent',
        body:
            'O seu evento necessita de alteracoes antes da publicacao. $reason',
      );
      _showSnack('Alteracoes solicitadas ao restaurante.', success: true);
      await _load();
      return true;
    } catch (error) {
      _showSnack('Nao foi possivel solicitar alteracoes: $error');
      return false;
    }
  }

  Future<bool> _rejectEvent(Map<String, dynamic> request) async {
    const reasons = [
      'Conteudo ofensivo',
      'Evento duplicado',
      'Documento invalido',
      'Informacoes falsas',
      'Outro',
    ];
    String reason = reasons.first;
    final notesController = TextEditingController();
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Rejeitar evento'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: reason,
                decoration: const InputDecoration(labelText: 'Motivo'),
                items: reasons
                    .map(
                      (item) =>
                          DropdownMenuItem(value: item, child: Text(item)),
                    )
                    .toList(),
                onChanged: (value) =>
                    setDialogState(() => reason = value ?? reasons.first),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Observacoes'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Rejeitar'),
            ),
          ],
        ),
      ),
    );
    if (submitted != true) return false;
    final fullReason = notesController.text.trim().isEmpty
        ? reason
        : '$reason: ${notesController.text.trim()}';
    try {
      await _service.rejectRequest(
        requestId: request['id'].toString(),
        reason: fullReason,
      );
      await _service.sendRequestMessage(
        requestId: request['id'].toString(),
        senderRole: 'marketing_agent',
        body: 'O seu evento foi rejeitado. Motivo: $fullReason',
      );
      _showSnack('Evento rejeitado.', success: true);
      await _load();
      return true;
    } catch (error) {
      _showSnack('Nao foi possivel rejeitar: $error');
      return false;
    }
  }

  String _shortDate(dynamic value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (parsed == null) return '-';
    return '${parsed.day.toString().padLeft(2, '0')}/${parsed.month.toString().padLeft(2, '0')}/${parsed.year}';
  }

  // Mantido temporariamente para pedidos antigos que ainda estejam em producao.
  // ignore: unused_element
  Future<void> _openRequestLegacy(Map<String, dynamic> request) async {
    final messages = await _service.fetchRequestMessages(
      request['id'].toString(),
    );
    final titleController = TextEditingController(
      text: request['campaign_title']?.toString().trim().isNotEmpty == true
          ? request['campaign_title'].toString()
          : request['event_name']?.toString() ?? '',
    );
    final descriptionController = TextEditingController(
      text:
          request['campaign_description']?.toString().trim().isNotEmpty == true
          ? request['campaign_description'].toString()
          : request['description']?.toString() ?? '',
    );
    final messageController = TextEditingController();
    String? posterUrl =
        request['poster_url']?.toString().trim().isNotEmpty == true
        ? request['poster_url'].toString()
        : null;
    String? bannerUrl =
        request['banner_url']?.toString().trim().isNotEmpty == true
        ? request['banner_url'].toString()
        : null;
    String? attachmentUrl;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Preparar campanha'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: 'Titulo da campanha',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Descricao profissional',
                  ),
                  minLines: 3,
                  maxLines: 5,
                ),
                const SizedBox(height: 12),
                _uploadTile(
                  title: 'Cartaz',
                  value: posterUrl,
                  onUpload: () async {
                    final uploaded = await _uploadMarketingImage('posters');
                    if (uploaded != null) {
                      setDialogState(() => posterUrl = uploaded);
                    }
                  },
                ),
                const SizedBox(height: 12),
                _uploadTile(
                  title: 'Banner',
                  value: bannerUrl,
                  onUpload: () async {
                    final uploaded = await _uploadMarketingImage('banners');
                    if (uploaded != null) {
                      setDialogState(() => bannerUrl = uploaded);
                    }
                  },
                ),
                const SizedBox(height: 16),
                _sectionTitle('Chat do pedido'),
                if (messages.isEmpty)
                  const Text('Sem mensagens neste pedido.')
                else
                  ...messages.map(
                    (message) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(
                        _senderLabel(message['sender_role']?.toString()),
                      ),
                      subtitle: Text(message['body']?.toString() ?? ''),
                    ),
                  ),
                const SizedBox(height: 8),
                TextField(
                  controller: messageController,
                  decoration: const InputDecoration(labelText: 'Mensagem'),
                  minLines: 2,
                  maxLines: 4,
                ),
                const SizedBox(height: 8),
                _uploadTile(
                  title: 'Anexo da mensagem',
                  value: attachmentUrl,
                  onUpload: () async {
                    final uploaded = await _uploadMarketingImage('chat');
                    if (uploaded != null) {
                      setDialogState(() => attachmentUrl = uploaded);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(true),
              icon: const Icon(Icons.send_outlined),
              label: const Text('Enviar para revisao'),
            ),
          ],
        ),
      ),
    );

    if (saved != true) return;
    try {
      await _service.saveMarketingDraft(
        requestId: request['id'].toString(),
        campaignTitle: titleController.text,
        campaignDescription: descriptionController.text,
        posterUrl: posterUrl,
        bannerUrl: bannerUrl,
      );
      if (messageController.text.trim().isNotEmpty) {
        await _service.sendRequestMessage(
          requestId: request['id'].toString(),
          senderRole: 'marketing_agent',
          body: messageController.text,
          attachmentUrl: attachmentUrl,
        );
      }
      _showSnack(
        'Campanha enviada para revisao do restaurante.',
        success: true,
      );
      await _load();
    } catch (error) {
      _showSnack('Erro ao guardar campanha: $error');
    }
  }

  String? _validateCampaignDraft({
    required String title,
    required String placement,
    required String campaignType,
    required DateTime startsAt,
    required DateTime endsAt,
    required String? imageUrl,
    required Map<String, dynamic>? selectedRestaurant,
    required Map<String, dynamic>? selectedEvent,
    required String couponCode,
    required String actionType,
    required String externalUrl,
    required String whatsapp,
    required String phone,
  }) {
    if (title.trim().isEmpty) return 'Informe o titulo da campanha.';
    if (!endsAt.isAfter(startsAt)) {
      return 'A data final deve ser maior que a data inicial.';
    }
    if (_requiresCampaignImage(placement, campaignType) &&
        (imageUrl == null || imageUrl.trim().isEmpty)) {
      return 'Esta campanha precisa de imagem ou banner.';
    }
    if ((placement == 'featured_restaurant' ||
            campaignType == 'featured_restaurant' ||
            actionType == 'open_restaurant') &&
        selectedRestaurant == null) {
      return 'Selecione o restaurante pelo nome.';
    }
    if ((placement == 'tickets' ||
            placement == 'events_today' ||
            campaignType == 'event' ||
            campaignType == 'ticket' ||
            actionType == 'open_event' ||
            actionType == 'buy_ticket') &&
        selectedEvent == null) {
      return 'Selecione o evento publicado.';
    }
    if ((campaignType == 'coupon' || actionType == 'activate_coupon') &&
        couponCode.trim().isEmpty) {
      return 'Informe o codigo promocional.';
    }
    if ((actionType == 'external_link' || actionType == 'custom_page') &&
        externalUrl.trim().isEmpty) {
      return 'Informe o link ou pagina personalizada.';
    }
    if (actionType == 'whatsapp' && whatsapp.trim().isEmpty) {
      return 'Informe o WhatsApp.';
    }
    if (actionType == 'call' && phone.trim().isEmpty) {
      return 'Informe o telefone.';
    }
    return null;
  }

  bool _requiresCampaignImage(String placement, String campaignType) {
    return {
          'home_banner',
          'daily_offer',
          'featured_restaurant',
          'events_today',
          'tickets',
          'smart_discovery',
        }.contains(placement) ||
        {
          'daily_offer',
          'featured_restaurant',
          'event',
          'ticket',
          'banner',
          'news',
          'smart_discovery',
        }.contains(campaignType);
  }

  Future<bool?> _showCampaignPreview({
    required String title,
    required String subtitle,
    required String description,
    required String placement,
    required String campaignType,
    required String? imageUrl,
    required String? restaurantName,
    required String? eventName,
    required DateTime startsAt,
    required DateTime endsAt,
    required String actionLabel,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pre-visualizar campanha'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: imageUrl?.trim().isNotEmpty == true
                      ? Image.network(
                          imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            color: AppColors.borderGray,
                            child: const Icon(Icons.broken_image_outlined),
                          ),
                        )
                      : Container(
                          color: AppColors.borderGray.withValues(alpha: 0.4),
                          child: const Icon(Icons.image_outlined),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                title.trim(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              if (subtitle.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle.trim(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (description.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  description.trim(),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.neutralGray),
                ),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  Chip(label: Text(_placementLabel(placement))),
                  Chip(label: Text(_campaignTypeLabel(campaignType))),
                  if (restaurantName?.trim().isNotEmpty == true)
                    Chip(label: Text(restaurantName!.trim())),
                  if (eventName?.trim().isNotEmpty == true)
                    Chip(label: Text(eventName!.trim())),
                ],
              ),
              const SizedBox(height: 10),
              Text('${_formatDateTime(startsAt)} - ${_formatDateTime(endsAt)}'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () {},
                child: Text(
                  actionLabel.trim().isEmpty ? 'Ver agora' : actionLabel.trim(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Voltar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.rocket_launch_outlined),
            label: const Text('Publicar no DeliGo App'),
          ),
        ],
      ),
    );
  }

  Widget _formSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w800,
          color: AppColors.primaryRed,
        ),
      ),
    );
  }

  Widget _horizontalChoice<T>({
    required String label,
    required T value,
    required List<T> values,
    required String Function(T value) labelBuilder,
    required ValueChanged<T> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final itemWidth = constraints.maxWidth >= 480
                ? (constraints.maxWidth - 12) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 12,
              runSpacing: 8,
              children: values.map((item) {
                final selected = item == value;
                return SizedBox(
                  width: itemWidth,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => onChanged(item),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 11,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.primaryRed.withValues(alpha: 0.08)
                            : Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: selected
                              ? AppColors.primaryRed
                              : AppColors.borderGray,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            selected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            size: 18,
                            color: selected
                                ? AppColors.primaryRed
                                : AppColors.neutralGray,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              labelBuilder(item),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              softWrap: false,
                              style: TextStyle(
                                fontWeight: selected
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _dateTimeTile({
    required String title,
    required DateTime value,
    required ValueChanged<DateTime> onChanged,
  }) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        leading: const Icon(Icons.event_available_outlined),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(_formatDateTime(value)),
        onTap: () async {
          final pickedDate = await showDatePicker(
            context: context,
            initialDate: value,
            firstDate: DateTime.now().subtract(const Duration(days: 1)),
            lastDate: DateTime.now().add(const Duration(days: 730)),
          );
          if (pickedDate == null || !mounted) return;
          final pickedTime = await showTimePicker(
            context: context,
            initialTime: TimeOfDay(hour: value.hour, minute: value.minute),
          );
          if (pickedTime == null) return;
          onChanged(
            DateTime(
              pickedDate.year,
              pickedDate.month,
              pickedDate.day,
              pickedTime.hour,
              pickedTime.minute,
            ),
          );
        },
      ),
    );
  }

  Widget _weekdaySelector({
    required Set<int> selected,
    required void Function(int day, bool selected) onChanged,
  }) {
    const labels = <int, String>{
      1: 'Seg',
      2: 'Ter',
      3: 'Qua',
      4: 'Qui',
      5: 'Sex',
      6: 'Sab',
      7: 'Dom',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Dias da semana',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 42,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: labels.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final day = labels.keys.elementAt(index);
              return FilterChip(
                selected: selected.contains(day),
                label: Text(labels[day]!),
                onSelected: (value) => onChanged(day, value),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _hourRangeSelector({
    required RangeValues value,
    required ValueChanged<RangeValues> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Horario: ${value.start.round().toString().padLeft(2, '0')}:00 - ${value.end.round().toString().padLeft(2, '0')}:00',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        RangeSlider(
          values: value,
          min: 0,
          max: 23,
          divisions: 23,
          labels: RangeLabels(
            '${value.start.round().toString().padLeft(2, '0')}:00',
            '${value.end.round().toString().padLeft(2, '0')}:00',
          ),
          onChanged: onChanged,
        ),
      ],
    );
  }

  String _formatDateTime(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$day/$month/${value.year} $hour:$minute';
  }

  Widget _selectionTile({
    required IconData icon,
    required String title,
    required String value,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        leading: Icon(icon),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(value, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: const Icon(Icons.search),
        onTap: onTap,
      ),
    );
  }

  Widget _uploadTile({
    required String title,
    required String? value,
    required Future<void> Function() onUpload,
  }) {
    final hasFile = value?.trim().isNotEmpty == true;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        leading: Icon(hasFile ? Icons.check_circle : Icons.upload_file),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          hasFile
              ? 'Imagem carregada da galeria'
              : 'Carregar imagem da galeria',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: FilledButton.icon(
          onPressed: onUpload,
          icon: const Icon(Icons.photo_library_outlined),
          label: const Text('Upload'),
        ),
      ),
    );
  }

  Future<String?> _uploadMarketingImage(String folder) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) {
      _showSnack('Sessao expirada. Entre novamente.');
      return null;
    }
    final uploaded = await _imageService.uploadImage(
      'restaurant-assets',
      '$userId/marketing/$folder',
    );
    if (uploaded == null && mounted) {
      _showSnack('Nao foi possivel carregar a imagem da galeria.');
    }
    return uploaded;
  }

  Future<String?> _uploadMarketingVideo(String folder) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) {
      _showSnack('Sessao expirada. Entre novamente.');
      return null;
    }
    final uploaded = await _imageService.uploadVideo(
      'restaurant-assets',
      '$userId/marketing/$folder',
      maxDuration: const Duration(seconds: 10),
      maxBytes: 30 * 1024 * 1024,
    );
    if (uploaded == null && mounted) {
      _showSnack(
        'Nao foi possivel carregar o video. Use video ate 10 segundos.',
      );
    }
    return uploaded;
  }

  Future<Map<String, dynamic>?> _pickRestaurant() async {
    final searchController = TextEditingController();
    var restaurants = await _service.searchRestaurantsForMarketing();
    if (!mounted) return null;
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.72,
              child: Column(
                children: [
                  TextField(
                    controller: searchController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Pesquisar restaurante',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (value) async {
                      final result = await _service
                          .searchRestaurantsForMarketing(value);
                      if (context.mounted) {
                        setSheetState(() => restaurants = result);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: restaurants.isEmpty
                        ? const Center(
                            child: Text('Nenhum restaurante encontrado.'),
                          )
                        : ListView.builder(
                            itemCount: restaurants.length,
                            itemBuilder: (context, index) {
                              final restaurant = restaurants[index];
                              final area =
                                  [
                                        restaurant['city'],
                                        restaurant['neighborhood'],
                                      ]
                                      .map((item) => item?.toString() ?? '')
                                      .where((item) => item.isNotEmpty)
                                      .join(' - ');
                              return ListTile(
                                leading: const CircleAvatar(
                                  child: Icon(Icons.storefront_outlined),
                                ),
                                title: Text(
                                  restaurant['name']?.toString() ??
                                      'Restaurante',
                                ),
                                subtitle: area.isEmpty ? null : Text(area),
                                onTap: () =>
                                    Navigator.of(context).pop(restaurant),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<Map<String, dynamic>?> _pickEvent() async {
    final events = await _service.fetchPublishedEvents();
    if (!mounted) return null;
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      builder: (context) => SafeArea(
        child: events.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Ainda nao existem eventos publicados.'),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: events.length,
                itemBuilder: (context, index) {
                  final event = events[index];
                  final restaurant = event['restaurants'] is Map
                      ? Map<String, dynamic>.from(event['restaurants'] as Map)
                      : const <String, dynamic>{};
                  return ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.event)),
                    title: Text(event['title']?.toString() ?? 'Evento'),
                    subtitle: Text(
                      [
                            restaurant['name'],
                            event['event_date'],
                            event['event_time'],
                          ]
                          .map((item) => item?.toString() ?? '')
                          .where((item) => item.isNotEmpty)
                          .join(' - '),
                    ),
                    onTap: () => Navigator.of(context).pop(event),
                  );
                },
              ),
      ),
    );
  }

  Widget _metricGrid(List<_MarketingMetric> metrics) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: metrics.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisExtent: 112,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemBuilder: (context, index) {
        final metric = metrics[index];
        return Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(metric.icon, color: AppColors.primaryRed),
                const Spacer(),
                Text(
                  metric.label,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  metric.value.toString(),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _sectionTitle(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
    ),
  );

  Widget _emptyCard(String text) => Card(
    elevation: 0,
    child: Padding(padding: const EdgeInsets.all(16), child: Text(text)),
  );

  Widget _profileRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );

  IconData _requestIcon(dynamic type) {
    switch (type?.toString()) {
      case 'live_music':
        return Icons.music_note;
      case 'karaoke':
        return Icons.mic_external_on_outlined;
      case 'dj_party':
        return Icons.graphic_eq;
      case 'happy_hour':
        return Icons.local_bar_outlined;
      case 'sports_event':
        return Icons.sports_soccer;
      default:
        return Icons.campaign_outlined;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'pending':
        return 'Novo';
      case 'received':
        return 'Recebido';
      case 'in_design':
        return 'Em producao';
      case 'ready_for_restaurant_review':
        return 'Aguardando restaurante';
      case 'approved':
        return 'Aprovado';
      case 'published':
        return 'Publicado';
      case 'sold_out':
        return 'Esgotado';
      case 'completed':
        return 'Finalizado';
      case 'cancelled':
        return 'Cancelado';
      case 'revision_requested':
        return 'Em revisao';
      case 'rejected':
        return 'Rejeitado';
      default:
        return status.isEmpty ? 'Estado' : status;
    }
  }

  String _placementLabel(String? value) {
    switch (value) {
      case 'home_banner':
        return 'Banner principal';
      case 'secondary_banner':
        return 'Banner secundario';
      case 'daily_offer':
        return 'Oferta do Dia';
      case 'featured_restaurant':
        return 'Restaurante em Destaque';
      case 'events_today':
        return 'Eventos Hoje';
      case 'tickets':
        return 'Bilhetes';
      case 'smart_discovery':
        return 'Descoberta Inteligente';
      case 'seasonal':
        return 'Novidades';
      case 'feed':
        return 'Feed';
      case 'category':
        return 'Categoria';
      case 'splash_screen':
        return 'Splash Screen';
      case 'video_ad':
        return 'Video Ad';
      case 'push':
        return 'Firebase Push';
      case 'campaign_center':
      default:
        return 'Centro de Campanhas';
    }
  }

  String _campaignTypeLabel(String? value) {
    switch (value) {
      case 'coupon':
        return 'Cupao';
      case 'daily_offer':
        return 'Oferta';
      case 'featured_restaurant':
        return 'Restaurante do Dia';
      case 'event':
        return 'Evento';
      case 'ticket':
        return 'Bilhete';
      case 'banner':
        return 'Banner';
      case 'news':
        return 'Novidade';
      case 'seasonal':
        return 'Sazonal';
      case 'smart_discovery':
        return 'Descoberta';
      case 'ad':
        return 'Anuncio';
      case 'deli':
        return 'Campanha DeliGo';
      case 'video':
        return 'Video';
      case 'sponsor':
        return 'Patrocinado';
      case 'push':
        return 'Push';
      case 'promotion':
      default:
        return 'Promocao';
    }
  }

  String _senderLabel(String? value) {
    switch (value) {
      case 'marketing_agent':
        return 'Marketing';
      case 'restaurant':
        return 'Restaurante';
      case 'admin':
        return 'Admin';
      default:
        return value?.isNotEmpty == true ? value! : '-';
    }
  }

  Future<void> _logout() async {
    AuthRefreshNotifier.markIntentionalSignOut();
    await Supabase.instance.client.auth.signOut();
    if (!mounted) return;
    context.go('/login');
  }

  void _showSnack(String message, {bool success = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: success
            ? AppColors.successGreen
            : AppColors.primaryRed,
        content: Text(message),
      ),
    );
  }
}

class _MarketingMetric {
  const _MarketingMetric(this.icon, this.label, this.value);

  final IconData icon;
  final String label;
  final int value;
}
