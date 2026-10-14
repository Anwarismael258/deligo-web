import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/theme/app_colors.dart';
import '../../services/marketing_service.dart';
import '../../services/restaurant_service.dart';

class RestaurantMarketingPage extends StatefulWidget {
  const RestaurantMarketingPage({super.key});

  @override
  State<RestaurantMarketingPage> createState() =>
      _RestaurantMarketingPageState();
}

class _RestaurantMarketingPageState extends State<RestaurantMarketingPage> {
  final _service = MarketingService(Supabase.instance.client);
  final _restaurantService = RestaurantService();
  final _imagePicker = ImagePicker();

  bool _loading = true;
  bool _validatingTicket = false;
  Map<String, dynamic>? _restaurant;
  List<Map<String, dynamic>> _requests = const [];
  List<Map<String, dynamic>> _events = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final restaurant = await _service.fetchRestaurantForCurrentUser();
      final restaurantId = restaurant?['id']?.toString();
      final requests = restaurantId == null
          ? const <Map<String, dynamic>>[]
          : await _service.fetchMarketingRequests(restaurantId: restaurantId);
      final events = restaurantId == null
          ? const <Map<String, dynamic>>[]
          : await _service.fetchPublishedEvents(restaurantId: restaurantId);
      if (!mounted) return;
      setState(() {
        _restaurant = restaurant;
        _requests = requests;
        _events = events;
      });
    } catch (error) {
      if (!mounted) return;
      _showSnack('Nao foi possivel carregar eventos: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Eventos DeliGo')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _restaurant == null ? null : _showNewRequestDialog,
        backgroundColor: AppColors.primaryRed,
        icon: const Icon(Icons.add),
        label: const Text('Novo Pedido'),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _hero(),
                    const SizedBox(height: 16),
                    _sectionTitle('Eventos publicados'),
                    if (_events.isEmpty)
                      _emptyCard('Ainda nao ha eventos publicados.')
                    else
                      ..._events.map(_eventCard),
                    const SizedBox(height: 16),
                    _sectionTitle('Pedidos para Marketing'),
                    if (_requests.isEmpty)
                      _emptyCard('Nenhum pedido enviado ainda.')
                    else
                      ..._requests.map(_requestCard),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _hero() {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const CircleAvatar(child: Icon(Icons.campaign_outlined)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _restaurant?['name']?.toString() ?? 'Restaurante',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Text(
                    'Solicite campanhas, promocoes, eventos e cartazes profissionais.',
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Validar bilhete',
              onPressed: _showValidateTicketDialog,
              icon: const Icon(Icons.qr_code_scanner),
            ),
          ],
        ),
      ),
    );
  }

  Widget _requestCard(Map<String, dynamic> request) {
    final status = request['status']?.toString() ?? 'pending';
    final needsResubmission =
        status == 'rejected' || status == 'revision_requested';
    return Card(
      elevation: 0,
      child: Column(
        children: [
          ListTile(
            leading: const CircleAvatar(child: Icon(Icons.assignment_outlined)),
            title: Text(request['event_name']?.toString() ?? 'Pedido'),
            subtitle: Text(
              '${_service.typeLabel(request['request_type']?.toString() ?? '')}\n'
              '${request['event_date'] ?? '-'} ${request['event_time'] ?? ''}',
            ),
            isThreeLine: true,
            trailing: Chip(label: Text(_statusLabel(status))),
            onTap: () => _openRequestConversation(request),
          ),
          if (needsResubmission)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (request['revision_notes']?.toString().trim().isNotEmpty ==
                      true)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Motivo: ${request['revision_notes']}',
                        style: const TextStyle(color: AppColors.primaryRed),
                      ),
                    ),
                  FilledButton.icon(
                    onPressed: () => _correctAndResubmit(request),
                    icon: const Icon(Icons.refresh_outlined),
                    label: const Text('Corrigir e reenviar'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _correctAndResubmit(Map<String, dynamic> request) async {
    final picked = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 82,
    );
    if (picked == null) return;

    _showSnack('A otimizar e carregar o novo banner...');
    final prepared = await _prepareEventBannerUpload(picked);
    if (prepared.error != null) {
      _showSnack(prepared.error!);
      return;
    }

    final ownerId =
        _restaurant?['owner_id']?.toString() ??
        Supabase.instance.client.auth.currentUser?.id;
    if (ownerId == null) {
      _showSnack('A sua sessao terminou. Entre novamente.');
      return;
    }

    final bannerUrl = await _restaurantService.uploadRestaurantAssetBytes(
      bytes: prepared.bytes!,
      ownerId: ownerId,
      folder: 'marketing',
      extension: 'jpg',
      contentType: 'image/jpeg',
    );
    if (bannerUrl == null) {
      _showSnack(
        _restaurantService.lastAssetUploadError ??
            'Nao foi possivel carregar o novo banner.',
      );
      return;
    }

    try {
      await _service.resubmitRestaurantRequest(
        requestId: request['id'].toString(),
        bannerUrl: bannerUrl,
      );
      _showSnack('Evento corrigido e reenviado para revisao.', success: true);
      await _load();
    } catch (error) {
      _showSnack('Nao foi possivel reenviar o evento: $error');
    }
  }

  Widget _eventCard(Map<String, dynamic> event) {
    final gross = (event['gross_revenue'] as num?)?.toDouble() ?? 0;
    final commission = (event['deligo_commission'] as num?)?.toDouble() ?? 0;
    final net = (event['net_amount'] as num?)?.toDouble() ?? 0;
    final sold = (event['tickets_sold'] as num?)?.toInt() ?? 0;
    final used = (event['tickets_used'] as num?)?.toInt() ?? 0;
    final quantity = (event['ticket_quantity'] as num?)?.toInt();
    final available = quantity == null
        ? null
        : (quantity - sold).clamp(0, quantity);
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.event_available, color: AppColors.primaryRed),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    event['title']?.toString() ?? 'Evento',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Chip(label: Text(event['status']?.toString() ?? 'published')),
              ],
            ),
            const SizedBox(height: 8),
            Text('${event['event_date'] ?? '-'} ${event['event_time'] ?? ''}'),
            Text(event['location']?.toString() ?? '-'),
            const Divider(),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _pill(
                  'Bilhetes vendidos',
                  '$sold${quantity == null ? '' : '/$quantity'}',
                ),
                _pill('Utilizados', '$used'),
                if (available != null)
                  _pill('Lugares disponiveis', '$available'),
                _pill('Receita', '${gross.toStringAsFixed(2)} MZN'),
                _pill(
                  'Comissao DeliGo',
                  '${commission.toStringAsFixed(2)} MZN',
                ),
                _pill('Liquido', '${net.toStringAsFixed(2)} MZN'),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _showEntryHistory(event),
                  icon: const Icon(Icons.history),
                  label: const Text('Entradas'),
                ),
                FilledButton.icon(
                  onPressed: _validatingTicket ? null : _showQrScannerDialog,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Scanner QR'),
                ),
                OutlinedButton.icon(
                  onPressed: net <= 0
                      ? null
                      : () => _showSnack(
                          'Carteira de eventos pronta para transferencia.',
                          success: true,
                        ),
                  icon: const Icon(Icons.account_balance_wallet_outlined),
                  label: const Text('Transferir Saldo'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showNewRequestDialog() async {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    final dateController = TextEditingController();
    final timeController = TextEditingController();
    final endTimeController = TextEditingController();
    final locationController = TextEditingController(
      text: _restaurant?['address']?.toString() ?? '',
    );
    final capacityController = TextEditingController();
    final salesStartController = TextEditingController();
    final salesEndController = TextEditingController();
    final colorsController = TextEditingController();
    final socialsController = TextEditingController();
    final websiteController = TextEditingController();
    final rulesController = TextEditingController();
    final refundPolicyController = TextEditingController();
    final notesController = TextEditingController();
    final ticketDrafts = <_EventTicketDraft>[_EventTicketDraft()];
    XFile? bannerFile;
    String? uploadedBannerUrl;
    String? bannerUploadError;
    bool uploadingBanner = false;
    DateTime? eventDate;
    TimeOfDay? eventTime;
    TimeOfDay? eventEndTime;
    DateTime? salesStartAt;
    DateTime? salesEndAt;
    String eventCategory = MarketingService.eventCategories.keys.first;
    String eventTypeDetail =
        MarketingService.eventCategories.values.first.first;
    String objective = 'increase_sales';
    String targetAudience = 'all';
    String ageRating = 'free';
    bool sellsTickets = false;

    final created = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Novo Pedido para Marketing'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: eventCategory,
                  decoration: const InputDecoration(labelText: 'Categoria'),
                  items: MarketingService.eventCategories.keys
                      .map(
                        (category) => DropdownMenuItem(
                          value: category,
                          child: Text(category),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setDialogState(() {
                      eventCategory = value;
                      eventTypeDetail =
                          MarketingService.eventCategories[value]!.first;
                    });
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: eventTypeDetail,
                  decoration: const InputDecoration(
                    labelText: 'Tipo de evento',
                  ),
                  items:
                      (MarketingService.eventCategories[eventCategory] ??
                              const <String>[])
                          .map(
                            (type) => DropdownMenuItem(
                              value: type,
                              child: Text(type),
                            ),
                          )
                          .toList(),
                  onChanged: (value) => setDialogState(
                    () => eventTypeDetail = value ?? eventTypeDetail,
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Chip(
                    avatar: const Icon(Icons.schedule, size: 18),
                    label: const Text('Revisao DeliGo: ate 24h'),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nome do Evento',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(labelText: 'Descricao'),
                  minLines: 2,
                  maxLines: 4,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: dateController,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'Data do evento',
                    hintText: 'Selecionar data',
                    suffixIcon: Icon(Icons.calendar_today_outlined),
                  ),
                  onTap: () async {
                    final picked = await _pickDate(eventDate);
                    if (picked == null) return;
                    setDialogState(() {
                      eventDate = picked;
                      dateController.text = _formatDate(picked);
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: timeController,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'Hora inicio',
                    hintText: 'Selecionar hora de inicio',
                    suffixIcon: Icon(Icons.schedule_outlined),
                  ),
                  onTap: () async {
                    final picked = await _pickTime(eventTime);
                    if (picked == null) return;
                    setDialogState(() {
                      eventTime = picked;
                      timeController.text = _formatTime(picked);
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: endTimeController,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'Hora fim',
                    hintText: 'Selecionar hora de fim',
                    suffixIcon: Icon(Icons.schedule_outlined),
                  ),
                  onTap: () async {
                    final picked = await _pickTime(eventEndTime);
                    if (picked == null) return;
                    setDialogState(() {
                      eventEndTime = picked;
                      endTimeController.text = _formatTime(picked);
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: locationController,
                  decoration: const InputDecoration(labelText: 'Localizacao'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: capacityController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Capacidade maxima',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: objective,
                  decoration: const InputDecoration(labelText: 'Objetivo'),
                  items: const [
                    DropdownMenuItem(
                      value: 'increase_sales',
                      child: Text('Aumentar vendas'),
                    ),
                    DropdownMenuItem(
                      value: 'promote_restaurant',
                      child: Text('Divulgar restaurante'),
                    ),
                    DropdownMenuItem(
                      value: 'launch_product',
                      child: Text('Lancar produto'),
                    ),
                    DropdownMenuItem(
                      value: 'attract_customers',
                      child: Text('Atrair novos clientes'),
                    ),
                    DropdownMenuItem(
                      value: 'loyalty',
                      child: Text('Fidelizar clientes'),
                    ),
                  ],
                  onChanged: (value) => setDialogState(
                    () => objective = value ?? 'increase_sales',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: targetAudience,
                  decoration: const InputDecoration(labelText: 'Publico-alvo'),
                  items: const [
                    DropdownMenuItem(value: 'young', child: Text('Jovens')),
                    DropdownMenuItem(value: 'adults', child: Text('Adultos')),
                    DropdownMenuItem(
                      value: 'families',
                      child: Text('Familias'),
                    ),
                    DropdownMenuItem(
                      value: 'companies',
                      child: Text('Empresas'),
                    ),
                    DropdownMenuItem(value: 'all', child: Text('Todos')),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => targetAudience = value ?? 'all'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: ageRating,
                  decoration: const InputDecoration(labelText: 'Faixa etaria'),
                  items: const [
                    DropdownMenuItem(value: 'free', child: Text('Livre')),
                    DropdownMenuItem(value: '16', child: Text('+16')),
                    DropdownMenuItem(value: '18', child: Text('+18')),
                    DropdownMenuItem(value: '21', child: Text('+21')),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => ageRating = value ?? 'free'),
                ),
                const SizedBox(height: 12),
                _uploadPickerTile(
                  icon: Icons.image_outlined,
                  title: 'Imagem-Banner',
                  subtitle: uploadingBanner
                      ? 'A validar e carregar banner...'
                      : bannerUploadError != null
                      ? bannerUploadError!
                      : uploadedBannerUrl != null
                      ? 'Banner carregado e pronto para revisao'
                      : bannerFile == null
                      ? 'Escolha qualquer imagem. O DeliGo otimiza automaticamente.'
                      : bannerFile!.name,
                  actionLabel: uploadingBanner
                      ? 'Aguarde'
                      : bannerFile == null
                      ? 'Escolher'
                      : 'Trocar',
                  onPressed: () async {
                    if (uploadingBanner) return;
                    final picked = await _imagePicker.pickImage(
                      source: ImageSource.gallery,
                      imageQuality: 82,
                    );
                    if (picked == null) return;
                    setDialogState(() {
                      bannerFile = picked;
                      uploadedBannerUrl = null;
                      bannerUploadError = null;
                      uploadingBanner = true;
                    });
                    final ownerId =
                        _restaurant!['owner_id']?.toString() ??
                        Supabase.instance.client.auth.currentUser?.id;
                    if (ownerId == null) {
                      setDialogState(() {
                        bannerUploadError =
                            'A sua sessao terminou. Entre novamente para carregar o banner.';
                        uploadingBanner = false;
                      });
                      return;
                    }
                    final preparedBanner = await _prepareEventBannerUpload(
                      picked,
                    );
                    if (!mounted) return;
                    if (preparedBanner.error != null) {
                      setDialogState(() {
                        bannerUploadError = preparedBanner.error;
                        uploadingBanner = false;
                      });
                      return;
                    }
                    var url = await _restaurantService
                        .uploadRestaurantAssetBytes(
                          bytes: preparedBanner.bytes!,
                          ownerId: ownerId,
                          folder: 'marketing',
                          extension: 'jpg',
                          contentType: 'image/jpeg',
                        );
                    url ??= await _restaurantService.uploadRestaurantAsset(
                      file: picked,
                      ownerId: ownerId,
                      folder: 'marketing_original',
                    );
                    if (!mounted) return;
                    setDialogState(() {
                      uploadedBannerUrl = url;
                      bannerUploadError = url == null
                          ? _restaurantService.lastAssetUploadError ??
                                'Nao foi possivel guardar o banner. Tente novamente.'
                          : null;
                      uploadingBanner = false;
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: colorsController,
                  decoration: const InputDecoration(
                    labelText: 'Cores da marca',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: socialsController,
                  decoration: const InputDecoration(labelText: 'Redes sociais'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: websiteController,
                  decoration: const InputDecoration(labelText: 'Website'),
                ),
                SwitchListTile(
                  value: sellsTickets,
                  title: const Text('Vender bilhetes'),
                  onChanged: (value) =>
                      setDialogState(() => sellsTickets = value),
                ),
                if (sellsTickets) ...[
                  ...ticketDrafts.map(
                    (ticket) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: ticket.nameController,
                              decoration: const InputDecoration(
                                labelText: 'Tipo',
                                hintText: 'Normal, VIP, Mesa',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: ticket.priceController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Preco',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: ticket.quantityController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Qtd',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => setDialogState(
                        () => ticketDrafts.add(_EventTicketDraft.empty()),
                      ),
                      icon: const Icon(Icons.add),
                      label: const Text('Adicionar outro bilhete'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: salesStartController,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: 'Inicio das vendas',
                      hintText: 'Selecionar data e hora',
                      suffixIcon: Icon(Icons.event_available_outlined),
                    ),
                    onTap: () async {
                      final picked = await _pickDateTime(salesStartAt);
                      if (picked == null) return;
                      setDialogState(() {
                        salesStartAt = picked;
                        salesStartController.text = _formatDateTime(picked);
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: salesEndController,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: 'Encerramento das vendas',
                      hintText: 'Selecionar data e hora',
                      suffixIcon: Icon(Icons.event_busy_outlined),
                    ),
                    onTap: () async {
                      final picked = await _pickDateTime(salesEndAt);
                      if (picked == null) return;
                      setDialogState(() {
                        salesEndAt = picked;
                        salesEndController.text = _formatDateTime(picked);
                      });
                    },
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: rulesController,
                  decoration: const InputDecoration(
                    labelText: 'Regras do evento',
                  ),
                  minLines: 2,
                  maxLines: 4,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: refundPolicyController,
                  decoration: const InputDecoration(
                    labelText: 'Politica de reembolso',
                  ),
                  minLines: 2,
                  maxLines: 4,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(
                    labelText: 'Observacoes para Marketing',
                  ),
                  minLines: 2,
                  maxLines: 4,
                ),
                const SizedBox(height: 12),
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.hourglass_top,
                    color: AppColors.primaryRed,
                  ),
                  title: Text('Status: Em revisao'),
                  subtitle: Text(
                    'Nossa equipe esta analisando seu evento. Tempo medio: ate 24 horas.',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Enviar para Revisao'),
            ),
          ],
        ),
      ),
    );

    if (created != true) return;
    try {
      if (eventDate == null || eventTime == null) {
        _showSnack('Selecione a data e a hora do evento.');
        return;
      }
      if (eventEndTime == null) {
        _showSnack('Selecione a hora de fim do evento.');
        return;
      }
      final ticketOptions = sellsTickets
          ? _ticketOptionsPayload(ticketDrafts)
          : const <Map<String, dynamic>>[];
      if (sellsTickets && ticketOptions.isEmpty) {
        _showSnack(
          'Adicione pelo menos um tipo de bilhete com preco e quantidade.',
        );
        return;
      }
      if (sellsTickets &&
          salesStartAt != null &&
          salesEndAt != null &&
          !salesEndAt!.isAfter(salesStartAt!)) {
        _showSnack('O encerramento das vendas deve ser depois do inicio.');
        return;
      }
      final ownerId = _restaurant!['id'].toString();
      if (uploadingBanner) {
        _showSnack('Aguarde o upload do banner terminar.');
        return;
      }
      if (bannerFile != null && uploadedBannerUrl == null) {
        _showSnack(
          bannerUploadError ??
              'Escolha um banner valido antes de enviar para revisao.',
        );
        return;
      }
      final firstTicket = ticketOptions.isEmpty ? null : ticketOptions.first;
      await _service.createRestaurantRequest(
        restaurantId: ownerId,
        requestType: _canonicalRequestType(eventTypeDetail),
        eventName: nameController.text,
        description: descriptionController.text,
        eventDate: _formatDate(eventDate!),
        eventTime: _formatTime(eventTime!),
        location: locationController.text,
        sellsTickets: sellsTickets,
        ticketPrice: (firstTicket?['price'] as num?)?.toDouble(),
        ticketQuantity: (firstTicket?['quantity'] as num?)?.toInt(),
        eventCategory: eventCategory,
        eventTypeDetail: eventTypeDetail,
        eventEndTime: _formatTime(eventEndTime!),
        maxCapacity: int.tryParse(capacityController.text),
        ticketOptions: ticketOptions,
        objective: objective,
        targetAudience: targetAudience,
        ageRating: ageRating,
        logoUrl: null,
        photoUrls: const [],
        bannerUrl: uploadedBannerUrl,
        brandColors: colorsController.text,
        socialLinks: socialsController.text,
        website: websiteController.text,
        salesStartAt: salesStartAt == null ? null : _toUtcIso(salesStartAt!),
        salesEndAt: salesEndAt == null ? null : _toUtcIso(salesEndAt!),
        rules: rulesController.text,
        refundPolicy: refundPolicyController.text,
        notes: notesController.text,
      );
      _showSnack(
        'Evento enviado para revisao. Tempo medio: ate 24h.',
        success: true,
      );
      await _load();
    } catch (error) {
      _showSnack('Erro ao enviar pedido: $error');
    }
  }

  Future<void> _approveRequest(Map<String, dynamic> request) async {
    try {
      await _service.approveAndPublishRequest(request['id'].toString());
      _showSnack('Evento publicado automaticamente na DeliGo.', success: true);
      await _load();
    } catch (error) {
      _showSnack('Erro ao publicar evento: $error');
    }
  }

  Future<void> _requestChanges(Map<String, dynamic> request) async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pedir alteracoes'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'O que deve ser alterado?',
          ),
          minLines: 3,
          maxLines: 5,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _service.requestRevision(
        requestId: request['id'].toString(),
        notes: controller.text,
      );
      _showSnack('Alteracoes enviadas para Marketing.', success: true);
      await _load();
    } catch (error) {
      _showSnack('Erro ao pedir alteracoes: $error');
    }
  }

  String _canonicalRequestType(String eventType) {
    final normalized = eventType.toLowerCase();
    if (normalized.contains('karaoke')) return 'karaoke';
    if (normalized.contains('dj')) return 'dj_party';
    if (normalized.contains('happy hour')) return 'happy_hour';
    if (normalized.contains('musica') ||
        normalized.contains('banda') ||
        normalized.contains('concerto') ||
        normalized.contains('jazz') ||
        normalized.contains('kizomba') ||
        normalized.contains('amapiano')) {
      return 'live_music';
    }
    if (normalized.contains('buffet') ||
        normalized.contains('rodizio') ||
        normalized.contains('brunch') ||
        normalized.contains('jantar') ||
        normalized.contains('gastronomico')) {
      return 'special_buffet';
    }
    if (normalized.contains('festa') ||
        normalized.contains('party') ||
        normalized.contains('reveillon') ||
        normalized.contains('carnaval')) {
      return 'theme_party';
    }
    if (normalized.contains('futebol') ||
        normalized.contains('ufc') ||
        normalized.contains('boxe') ||
        normalized.contains('rugby') ||
        normalized.contains('basquetebol')) {
      return 'sports_event';
    }
    if (normalized.contains('teatro') ||
        normalized.contains('cultura') ||
        normalized.contains('danca') ||
        normalized.contains('exposicao')) {
      return 'cultural_event';
    }
    if (normalized.contains('workshop') ||
        normalized.contains('conferencia') ||
        normalized.contains('networking') ||
        normalized.contains('curso')) {
      return 'corporate_event';
    }
    return 'other';
  }

  List<Map<String, dynamic>> _ticketOptionsPayload(
    List<_EventTicketDraft> drafts,
  ) {
    final options = <Map<String, dynamic>>[];
    for (final draft in drafts) {
      final name = draft.nameController.text.trim();
      final price = double.tryParse(
        draft.priceController.text.trim().replaceAll(',', '.'),
      );
      final quantity = int.tryParse(draft.quantityController.text.trim());
      if (name.isEmpty ||
          price == null ||
          price <= 0 ||
          quantity == null ||
          quantity <= 0) {
        continue;
      }
      options.add({'name': name, 'price': price, 'quantity': quantity});
    }
    return options;
  }

  Future<_PreparedBannerUpload> _prepareEventBannerUpload(XFile file) async {
    final originalBytes = await file.readAsBytes();
    if (originalBytes.isEmpty) {
      return const _PreparedBannerUpload.error(
        'A imagem selecionada esta vazia.',
      );
    }

    for (final quality in const [82, 76, 70, 64, 58]) {
      final compressed = await FlutterImageCompress.compressWithList(
        originalBytes,
        minWidth: 1080,
        minHeight: 1,
        quality: quality,
        format: CompressFormat.jpeg,
        keepExif: false,
      );
      if (compressed.isNotEmpty && compressed.length <= 2 * 1024 * 1024) {
        return _PreparedBannerUpload.bytes(compressed);
      }
    }

    if (originalBytes.length <= 2 * 1024 * 1024) {
      return _PreparedBannerUpload.bytes(originalBytes);
    }
    return const _PreparedBannerUpload.error(
      'Imagem muito pesada. O DeliGo tentou otimizar automaticamente; escolha outra imagem ou screenshot.',
    );
  }

  Future<void> _showValidateTicketDialog() async {
    final controller = TextEditingController();
    final submitted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Validar entrada'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'QR Code ou codigo unico',
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Navigator.of(context).pop(false);
              _showQrScannerDialog();
            },
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scanner'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.verified_outlined),
            label: const Text('Validar'),
          ),
        ],
      ),
    );
    if (submitted != true || controller.text.trim().isEmpty) return;
    await _validateTicketCode(controller.text);
  }

  Future<void> _showQrScannerDialog() async {
    var handled = false;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Scanner QR'),
        contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        content: SizedBox(
          width: 360,
          height: 360,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: MobileScanner(
              onDetect: (capture) {
                if (handled) return;
                final code = capture.barcodes
                    .map((barcode) => barcode.rawValue?.trim() ?? '')
                    .firstWhere((value) => value.isNotEmpty, orElse: () => '');
                if (code.isEmpty) return;
                handled = true;
                Navigator.of(context).pop();
                _validateTicketCode(code);
              },
            ),
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

  Future<void> _validateTicketCode(String code) async {
    if (_validatingTicket || code.trim().isEmpty) return;
    setState(() => _validatingTicket = true);
    try {
      final result = await _service.validateTicket(code);
      if (result['success'] == true) {
        _showSnack('Entrada autorizada.', success: true);
        await _load();
        return;
      }
      final error = result['error']?.toString() ?? 'ticket_invalid';
      _showSnack(switch (error) {
        'ticket_already_used' => 'Bilhete ja utilizado.',
        'event_cancelled' => 'Bilhete cancelado. A entrada nao e permitida.',
        'event_completed' => 'Este evento ja foi finalizado.',
        _ => 'Bilhete invalido ou indisponivel.',
      });
    } catch (error) {
      _showSnack('Erro ao validar bilhete: $error');
    } finally {
      if (mounted) setState(() => _validatingTicket = false);
    }
  }

  Future<void> _showEntryHistory(Map<String, dynamic> event) async {
    final eventId = event['id']?.toString() ?? '';
    if (eventId.isEmpty) return;
    try {
      final tickets = await _service.fetchEventTickets(
        eventId: eventId,
        status: 'used',
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Entradas - ${event['title'] ?? 'Evento'}'),
          content: SizedBox(
            width: 520,
            child: tickets.isEmpty
                ? const Text('Ainda nao ha entradas validadas.')
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: tickets.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final ticket = tickets[index];
                      final buyer = ticket['profiles'] is Map
                          ? Map<String, dynamic>.from(ticket['profiles'] as Map)
                          : const <String, dynamic>{};
                      final validator = ticket['validator'] is Map
                          ? Map<String, dynamic>.from(
                              ticket['validator'] as Map,
                            )
                          : const <String, dynamic>{};
                      final buyerName =
                          buyer['full_name']?.toString().trim().isNotEmpty ==
                              true
                          ? buyer['full_name'].toString()
                          : 'Cliente';
                      return ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.verified_outlined),
                        ),
                        title: Text(buyerName),
                        subtitle: Text(
                          'Codigo: ${ticket['ticket_code'] ?? '-'}\n'
                          'Entrada: ${_formatDateTimeText(ticket['used_at'])}\n'
                          'Validado por: ${validator['full_name'] ?? '-'}',
                        ),
                        isThreeLine: true,
                      );
                    },
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
    } catch (error) {
      _showSnack('Nao foi possivel abrir historico: $error');
    }
  }

  Future<void> _openRequestConversation(Map<String, dynamic> request) async {
    final messages = await _service.fetchRequestMessages(
      request['id'].toString(),
    );
    final messageController = TextEditingController();
    XFile? attachmentFile;
    final sent = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(request['event_name']?.toString() ?? 'Pedido'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                const SizedBox(height: 12),
                TextField(
                  controller: messageController,
                  decoration: const InputDecoration(labelText: 'Mensagem'),
                  minLines: 2,
                  maxLines: 4,
                ),
                const SizedBox(height: 8),
                _uploadPickerTile(
                  icon: Icons.attach_file,
                  title: 'Anexo',
                  subtitle: attachmentFile == null
                      ? 'Carregar imagem da galeria'
                      : attachmentFile!.name,
                  actionLabel: attachmentFile == null ? 'Upload' : 'Trocar',
                  onPressed: () async {
                    final picked = await _imagePicker.pickImage(
                      source: ImageSource.gallery,
                      maxWidth: 1600,
                      maxHeight: 1600,
                      imageQuality: 88,
                    );
                    if (picked != null) {
                      setDialogState(() => attachmentFile = picked);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Fechar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Enviar'),
            ),
          ],
        ),
      ),
    );
    if (sent != true || messageController.text.trim().isEmpty) return;
    try {
      String? attachmentUrl;
      if (attachmentFile != null) {
        final ownerId =
            _restaurant?['owner_id']?.toString() ??
            Supabase.instance.client.auth.currentUser?.id ??
            'restaurant';
        attachmentUrl = await _restaurantService.uploadRestaurantAsset(
          file: attachmentFile!,
          ownerId: ownerId,
          folder: 'marketing_chat',
        );
        if (attachmentUrl == null) {
          throw Exception('Falha ao enviar o anexo.');
        }
      }
      await _service.sendRequestMessage(
        requestId: request['id'].toString(),
        senderRole: 'restaurant',
        body: messageController.text,
        attachmentUrl: attachmentUrl,
      );
      _showSnack('Mensagem enviada.', success: true);
    } catch (error) {
      _showSnack('Erro ao enviar mensagem: $error');
    }
  }

  Widget _uploadPickerTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required String actionLabel,
    required VoidCallback onPressed,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.borderGray),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primaryRed),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.neutralGray),
                ),
              ],
            ),
          ),
          TextButton(onPressed: onPressed, child: Text(actionLabel)),
        ],
      ),
    );
  }

  Future<DateTime?> _pickDate(DateTime? initial) {
    final now = DateTime.now();
    return showDatePicker(
      context: context,
      initialDate: initial ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 3),
    );
  }

  Future<TimeOfDay?> _pickTime(TimeOfDay? initial) {
    return showTimePicker(
      context: context,
      initialTime: initial ?? TimeOfDay.now(),
    );
  }

  Future<DateTime?> _pickDateTime(DateTime? initial) async {
    final date = await _pickDate(initial);
    if (date == null) return null;
    if (!mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: initial == null
          ? TimeOfDay.now()
          : TimeOfDay(hour: initial.hour, minute: initial.minute),
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  String _formatDate(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  String _formatTime(TimeOfDay value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _formatDateTime(DateTime value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '${_formatDate(value)} $hour:$minute';
  }

  String _formatDateTimeText(Object? value) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return '-';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    return _formatDateTime(parsed.toLocal());
  }

  String _toUtcIso(DateTime value) => value.toUtc().toIso8601String();

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

  Widget _pill(String label, String value) =>
      Chip(label: Text('$label: $value'));

  String _statusLabel(String status) {
    switch (status) {
      case 'pending':
        return 'Enviado';
      case 'received':
        return 'Recebido';
      case 'revision_requested':
        return 'Necessita alteracoes';
      case 'rejected':
        return 'Rejeitado';
      case 'ready_for_restaurant_review':
        return 'Rever e confirmar';
      case 'published':
        return 'Publicado';
      default:
        return status;
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

class _EventTicketDraft {
  _EventTicketDraft({
    String name = 'Normal',
    String price = '',
    String quantity = '',
  }) : nameController = TextEditingController(text: name),
       priceController = TextEditingController(text: price),
       quantityController = TextEditingController(text: quantity);

  _EventTicketDraft.empty() : this(name: '', price: '', quantity: '');

  final TextEditingController nameController;
  final TextEditingController priceController;
  final TextEditingController quantityController;
}

class _PreparedBannerUpload {
  const _PreparedBannerUpload.bytes(this.bytes) : error = null;

  const _PreparedBannerUpload.error(this.error) : bytes = null;

  final Uint8List? bytes;
  final String? error;
}
