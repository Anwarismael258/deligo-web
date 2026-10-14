import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/theme/app_colors.dart';
import '../../services/marketing_service.dart';

class CampaignDetailPage extends StatefulWidget {
  const CampaignDetailPage({
    super.key,
    required this.campaignId,
    this.initialCampaign,
  });

  final String campaignId;
  final Map<String, dynamic>? initialCampaign;

  @override
  State<CampaignDetailPage> createState() => _CampaignDetailPageState();
}

class _CampaignDetailPageState extends State<CampaignDetailPage> {
  final _service = MarketingService(Supabase.instance.client);

  bool _loading = true;
  Map<String, dynamic>? _campaign;
  Map<String, dynamic>? _event;

  @override
  void initState() {
    super.initState();
    _campaign = widget.initialCampaign;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final campaign =
          _campaign ?? await _service.fetchCampaignById(widget.campaignId);
      final eventId =
          campaign?['event_id']?.toString() ??
          (widget.campaignId.startsWith('event-') ? widget.campaignId : '');
      final event = eventId.trim().isEmpty
          ? null
          : await _service.fetchEventById(eventId);
      if (!mounted) return;
      setState(() {
        _campaign = campaign;
        _event = event;
      });
    } catch (error) {
      if (mounted) _showSnack('Nao foi possivel carregar: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _event ?? _campaign;
    return Scaffold(
      appBar: AppBar(title: const Text('Detalhes')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : data == null
          ? const Center(child: Text('Conteudo indisponivel.'))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  _heroImage(data),
                  const SizedBox(height: 16),
                  Text(
                    _title(data),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_subtitle(data).isNotEmpty)
                    Text(
                      _subtitle(data),
                      style: const TextStyle(color: AppColors.neutralGray),
                    ),
                  const SizedBox(height: 16),
                  _detailsGrid(data),
                  const SizedBox(height: 16),
                  _restaurantCard(data),
                  const SizedBox(height: 16),
                  if (_description(data).isNotEmpty) _descriptionCard(data),
                  const SizedBox(height: 16),
                  _gallery(data),
                  const SizedBox(height: 16),
                  _contactActions(data),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () => _handlePrimaryAction(data),
                    icon: Icon(_primaryIcon(data)),
                    label: Text(_primaryLabel(data)),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _heroImage(Map<String, dynamic> data) {
    final imageUrl = _imageUrl(data);
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 220,
        color: AppColors.primaryRed.withValues(alpha: 0.08),
        child: imageUrl.isEmpty
            ? const Center(
                child: Icon(
                  Icons.campaign_outlined,
                  color: AppColors.primaryRed,
                  size: 56,
                ),
              )
            : CachedNetworkImage(imageUrl: imageUrl, fit: BoxFit.cover),
      ),
    );
  }

  Widget _detailsGrid(Map<String, dynamic> data) {
    final chips = <Widget>[
      if (_eventDate(data).isNotEmpty)
        _infoChip(Icons.event_outlined, _eventDate(data)),
      if (_eventTime(data).isNotEmpty)
        _infoChip(Icons.schedule_outlined, _eventTime(data)),
      if (_location(data).isNotEmpty)
        _infoChip(Icons.place_outlined, _location(data)),
      if (_campaignType(data).isNotEmpty)
        _infoChip(Icons.sell_outlined, _campaignType(data)),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 8, runSpacing: 8, children: chips);
  }

  Widget _restaurantCard(Map<String, dynamic> data) {
    final restaurant = _restaurant(data);
    final name = restaurant['name']?.toString() ?? '';
    if (name.isEmpty) return const SizedBox.shrink();
    return Card(
      elevation: 0,
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.restaurant_outlined)),
        title: Text(name),
        subtitle: Text(
          [
            restaurant['neighborhood']?.toString(),
            restaurant['city']?.toString(),
          ].where((item) => item?.trim().isNotEmpty == true).join(' - '),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          final id =
              data['restaurant_id']?.toString() ?? restaurant['id']?.toString();
          if (id != null && id.isNotEmpty) context.push('/restaurant/$id');
        },
      ),
    );
  }

  Widget _descriptionCard(Map<String, dynamic> data) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(_description(data)),
      ),
    );
  }

  Widget _gallery(Map<String, dynamic> data) {
    final urls = _galleryUrls(data);
    if (urls.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Galeria',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 110,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: urls.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) => ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(
                imageUrl: urls[index],
                width: 150,
                fit: BoxFit.cover,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _contactActions(Map<String, dynamic> data) {
    final restaurant = _restaurant(data);
    final phone = _metadata(data, 'phone') ?? restaurant['phone']?.toString();
    final website = _metadata(data, 'website');
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (_location(data).isNotEmpty)
          OutlinedButton.icon(
            onPressed: () => _openExternal(
              'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(_location(data))}',
            ),
            icon: const Icon(Icons.map_outlined),
            label: const Text('Mapa'),
          ),
        if (phone?.trim().isNotEmpty == true)
          OutlinedButton.icon(
            onPressed: () => _openExternal('tel:${phone!.trim()}'),
            icon: const Icon(Icons.call_outlined),
            label: const Text('Ligar'),
          ),
        if (website?.trim().isNotEmpty == true)
          OutlinedButton.icon(
            onPressed: () => _openExternal(website!.trim()),
            icon: const Icon(Icons.language_outlined),
            label: const Text('Website'),
          ),
      ],
    );
  }

  Widget _infoChip(IconData icon, String label) {
    return Chip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }

  Future<void> _handlePrimaryAction(Map<String, dynamic> data) async {
    final actionType = _metadata(data, 'action_type') ?? '';
    if (actionType == 'external_link' || actionType == 'custom_page') {
      final externalUrl = _metadata(data, 'external_url');
      if (externalUrl?.trim().isNotEmpty == true) {
        await _openExternal(externalUrl!.trim());
        return;
      }
    }
    if (actionType == 'whatsapp') {
      final phone = _metadata(data, 'whatsapp') ?? _metadata(data, 'phone');
      if (phone?.trim().isNotEmpty == true) {
        await _openExternal('https://wa.me/${_digitsOnly(phone!)}');
        return;
      }
    }
    if (actionType == 'call') {
      final phone =
          _metadata(data, 'phone') ?? _restaurant(data)['phone']?.toString();
      if (phone?.trim().isNotEmpty == true) {
        await _openExternal('tel:${phone!.trim()}');
        return;
      }
    }
    if (actionType == 'open_location') {
      await _openExternal(
        'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(_location(data))}',
      );
      return;
    }
    if (_isTicket(data) || actionType == 'buy_ticket') {
      await _buyTicket(data);
      return;
    }
    if (_isCoupon(data) || actionType == 'activate_coupon') {
      await _activateCoupon(data);
      return;
    }
    final restaurantId = data['restaurant_id']?.toString();
    if (restaurantId != null && restaurantId.isNotEmpty) {
      context.push('/restaurant/$restaurantId');
      return;
    }
    final externalUrl = _metadata(data, 'external_url');
    if (externalUrl?.trim().isNotEmpty == true) {
      await _openExternal(externalUrl!.trim());
    }
  }

  Future<void> _buyTicket(Map<String, dynamic> data) async {
    final eventId =
        _event?['id']?.toString() ?? data['event_id']?.toString() ?? '';
    if (eventId.isEmpty) {
      _showSnack('Evento indisponivel para compra.');
      return;
    }
    final ticketTypes = await _service.fetchEventTicketTypes(eventId);
    String? selectedTicketTypeId;
    for (final type in ticketTypes) {
      final id = type['id']?.toString();
      final remaining = (type['remaining'] as num?)?.toInt();
      if (id?.isNotEmpty == true && remaining != 0) {
        selectedTicketTypeId = id;
        break;
      }
    }
    var quantity = 1;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          Map<String, dynamic>? selectedType;
          for (final type in ticketTypes) {
            if (type['id']?.toString() == selectedTicketTypeId) {
              selectedType = type;
              break;
            }
          }
          final unitPrice =
              (selectedType?['price'] as num?)?.toDouble() ??
              (_event?['ticket_price'] as num?)?.toDouble() ??
              0;
          final remaining = (selectedType?['remaining'] as num?)?.toInt();
          final maxQuantity = remaining == null || remaining <= 0
              ? 99
              : remaining;
          if (quantity > maxQuantity) quantity = maxQuantity;
          return AlertDialog(
            title: const Text('Escolha o seu bilhete'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (ticketTypes.isNotEmpty)
                    ...ticketTypes.map((type) {
                      final id = type['id']?.toString() ?? '';
                      final name = type['ticket_name']?.toString() ?? 'Bilhete';
                      final price = (type['price'] as num?)?.toDouble() ?? 0;
                      final itemRemaining =
                          (type['remaining'] as num?)?.toInt() ?? 0;
                      final soldOut =
                          type['status'] == 'sold_out' || itemRemaining <= 0;
                      return RadioListTile<String>(
                        value: id,
                        groupValue: selectedTicketTypeId,
                        onChanged: soldOut
                            ? null
                            : (value) => setDialogState(() {
                                selectedTicketTypeId = value;
                                quantity = 1;
                              }),
                        title: Text('$name - ${price.toStringAsFixed(0)} MT'),
                        subtitle: Text(
                          soldOut ? 'Esgotado' : '$itemRemaining disponiveis',
                        ),
                      );
                    }),
                  if (ticketTypes.isEmpty)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.confirmation_number_outlined),
                      title: const Text('Normal'),
                      subtitle: Text('${unitPrice.toStringAsFixed(0)} MT'),
                    ),
                  const Divider(),
                  Row(
                    children: [
                      IconButton(
                        onPressed: quantity <= 1
                            ? null
                            : () => setDialogState(() => quantity--),
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                      Expanded(
                        child: Center(
                          child: Text(
                            '$quantity',
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: quantity >= maxQuantity
                            ? null
                            : () => setDialogState(() => quantity++),
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Total: ${(unitPrice * quantity).toStringAsFixed(0)} MT',
                    style: const TextStyle(fontWeight: FontWeight.w800),
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
                onPressed:
                    ticketTypes.isNotEmpty && selectedTicketTypeId == null
                    ? null
                    : () => Navigator.of(context).pop(true),
                child: const Text('Continuar'),
              ),
            ],
          );
        },
      ),
    );
    if (confirmed != true) return;

    Map<String, dynamic>? selectedType;
    for (final type in ticketTypes) {
      if (type['id']?.toString() == selectedTicketTypeId) {
        selectedType = type;
        break;
      }
    }
    final ticketName = selectedType?['ticket_name']?.toString() ?? 'Normal';
    final unitPrice =
        (selectedType?['price'] as num?)?.toDouble() ??
        (_event?['ticket_price'] as num?)?.toDouble() ??
        0;
    final total = unitPrice * quantity;
    final purchaseConfirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Resumo da compra'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _event?['title']?.toString() ?? 'Evento DeliGo',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Text('Bilhete: $ticketName'),
            Text('Quantidade: $quantity'),
            Text('Preco unitario: ${unitPrice.toStringAsFixed(2)} MT'),
            const Divider(height: 24),
            Text(
              'Total: ${total.toStringAsFixed(2)} MT',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            const Text('Pagamento com saldo da Wallet DeliGo.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Confirmar compra'),
          ),
        ],
      ),
    );
    if (purchaseConfirmed != true) return;

    try {
      final tickets = await _service.buyEventTickets(
        eventId: eventId,
        quantity: quantity,
        ticketTypeId: selectedTicketTypeId,
      );
      if (!mounted) return;
      final action = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.check_circle, color: Colors.green, size: 58),
          title: const Text('Compra concluida!'),
          content: const Text(
            'O seu bilhete foi emitido com sucesso e guardado na Wallet DeliGo.',
            textAlign: TextAlign.center,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop('event'),
              child: const Text('Voltar ao Evento'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop('ticket'),
              child: const Text('Ver Bilhete'),
            ),
          ],
        ),
      );
      if (action == 'ticket' && mounted) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Bilhete digital'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: tickets.map(_ticketTile).toList(),
              ),
            ),
            actions: [
              FilledButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  context.push('/wallet?section=tickets');
                },
                child: const Text('Abrir Meus Bilhetes'),
              ),
            ],
          ),
        );
      }
      await _load();
    } catch (error) {
      final normalized = error.toString().toLowerCase();
      if (normalized.contains('insufficient_available_balance') ||
          normalized.contains('insufficient_balance')) {
        await _showInsufficientWalletDialog();
        return;
      }
      if (normalized.contains('ticket_sales_not_open')) {
        _showSnack('As vendas deste evento ainda nao abriram.');
        return;
      }
      if (normalized.contains('ticket_sales_closed')) {
        _showSnack('As vendas deste evento ja encerraram.');
        return;
      }
      if (normalized.contains('event_sold_out')) {
        _showSnack('Este evento ja nao tem lugares disponiveis.');
        return;
      }
      if (normalized.contains('wallet_not_found')) {
        _showSnack('Crie ou carregue a sua Wallet DeliGo antes da compra.');
        return;
      }
      if (normalized.contains('ticket_type_unavailable') ||
          normalized.contains('ticket_type_required')) {
        _showSnack('O tipo de bilhete selecionado ja nao esta disponivel.');
        return;
      }
      if (normalized.contains('event_not_available_for_ticket_sale')) {
        _showSnack('Este evento nao esta disponivel para venda de bilhetes.');
        return;
      }
      debugPrint('Erro tecnico ao comprar bilhete: $error');
      _showSnack(
        'Nao foi possivel concluir a compra. Nenhum valor foi debitado.',
      );
    }
  }

  Future<void> _showInsufficientWalletDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Saldo insuficiente'),
        content: const Text(
          'Carregue a Wallet DeliGo com M-Pesa ou e-Mola para comprar este bilhete.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              context.push('/wallet?section=deposit');
            },
            child: const Text('Carregar Wallet'),
          ),
        ],
      ),
    );
  }

  Widget _ticketTile(Map<String, dynamic> ticket) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: QrImageView(
                data: ticket['qr_code']?.toString() ?? '',
                version: QrVersions.auto,
                size: 150,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            SelectableText(
              ticket['qr_code']?.toString() ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            if (ticket['ticket_type_name']?.toString().isNotEmpty == true)
              Text('Tipo: ${ticket['ticket_type_name']}'),
            Text('Codigo: ${ticket['ticket_code'] ?? '-'}'),
            Text('Estado: ${ticket['status'] ?? 'sold'}'),
          ],
        ),
      ),
    );
  }

  Future<void> _activateCoupon(Map<String, dynamic> data) async {
    final code = data['coupon_code']?.toString() ?? '';
    if (code.isEmpty) {
      _showSnack('Cupao indisponivel.');
      return;
    }
    try {
      await _service.applyCouponCode(code);
      _showSnack('Cupao guardado na Wallet.', success: true);
    } catch (error) {
      _showSnack('Nao foi possivel ativar cupao: $error');
    }
  }

  Future<void> _openExternal(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String _digitsOnly(String value) {
    return value.replaceAll(RegExp(r'[^0-9]'), '');
  }

  String _title(Map<String, dynamic> data) =>
      data['title']?.toString() ?? data['event_name']?.toString() ?? 'DeliGo';

  String _subtitle(Map<String, dynamic> data) =>
      data['subtitle']?.toString() ??
      _restaurant(data)['name']?.toString() ??
      '';

  String _description(Map<String, dynamic> data) =>
      data['description']?.toString() ?? '';

  String _imageUrl(Map<String, dynamic> data) {
    return data['image_url']?.toString() ??
        data['banner_url']?.toString() ??
        data['poster_url']?.toString() ??
        '';
  }

  String _eventDate(Map<String, dynamic> data) =>
      data['event_date']?.toString() ??
      _metadata(data, 'event_date') ??
      data['starts_at']?.toString().split('T').first ??
      '';

  String _eventTime(Map<String, dynamic> data) =>
      data['event_time']?.toString() ?? _metadata(data, 'event_time') ?? '';

  String _location(Map<String, dynamic> data) =>
      data['location']?.toString() ?? _metadata(data, 'location') ?? '';

  String _campaignType(Map<String, dynamic> data) =>
      data['campaign_type']?.toString() ?? data['event_type']?.toString() ?? '';

  Map<String, dynamic> _restaurant(Map<String, dynamic> data) {
    return data['restaurants'] is Map
        ? Map<String, dynamic>.from(data['restaurants'] as Map)
        : const <String, dynamic>{};
  }

  List<String> _galleryUrls(Map<String, dynamic> data) {
    final metadata = (data['metadata'] as Map?)?.cast<String, dynamic>();
    final raw = metadata?['gallery'] ?? metadata?['photo_urls'];
    if (raw is List) {
      return raw
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    return const [];
  }

  bool _isTicket(Map<String, dynamic> data) {
    return data['sells_tickets'] == true ||
        data['campaign_type']?.toString() == 'ticket' ||
        data['placement']?.toString() == 'tickets';
  }

  bool _isCoupon(Map<String, dynamic> data) {
    return data['campaign_type']?.toString() == 'coupon' ||
        data['coupon_code']?.toString().isNotEmpty == true;
  }

  String _primaryLabel(Map<String, dynamic> data) {
    if (_isTicket(data)) return 'Comprar Bilhete';
    if (_isCoupon(data)) return 'Ativar Cupao';
    return data['action_label']?.toString() ?? 'Ver agora';
  }

  IconData _primaryIcon(Map<String, dynamic> data) {
    if (_isTicket(data)) return Icons.confirmation_number_outlined;
    if (_isCoupon(data)) return Icons.card_giftcard;
    return Icons.arrow_forward_rounded;
  }

  String? _metadata(Map<String, dynamic> data, String key) {
    final metadata = (data['metadata'] as Map?)?.cast<String, dynamic>();
    return metadata?[key]?.toString();
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
