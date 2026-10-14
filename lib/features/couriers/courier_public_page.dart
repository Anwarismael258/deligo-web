import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/theme/app_colors.dart';
import '../../services/order_service.dart';
import '../../services/public_share_service.dart';
import '../../shared/platform/share_card_saver.dart';
import '../../shared/utils/location_display.dart';

class CourierPublicPage extends StatefulWidget {
  final String courierId;
  final String? orderId;

  const CourierPublicPage({super.key, required this.courierId, this.orderId});

  @override
  State<CourierPublicPage> createState() => _CourierPublicPageState();
}

class _CourierPublicPageState extends State<CourierPublicPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final OrderService _orderService = OrderService();
  final PublicShareService _publicShareService = PublicShareService.instance;
  final TextEditingController _commentController = TextEditingController();
  final GlobalKey _shareCardKey = GlobalKey();

  bool _isLoading = true;
  bool _isSubmittingReview = false;
  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _courier;
  Map<String, dynamic>? _orderSummary;
  List<Map<String, dynamic>> _recentReviews = const [];
  Map<String, dynamic>? _existingReview;
  int _selectedRating = 5;
  double _averageMinutes = 0;
  double _satisfactionRate = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      final results = await Future.wait<dynamic>([
        _supabase
            .from('profiles')
            .select('full_name, avatar_url, phone')
            .eq('id', widget.courierId)
            .maybeSingle()
            .catchError((_) => null),
        _supabase
            .from('couriers')
            .select('*')
            .eq('id', widget.courierId)
            .maybeSingle()
            .catchError((_) => null),
        _supabase
            .from('courier_reviews')
            .select(
              'id, reviewer_id, reviewer_name, rating, comment, created_at, is_pinned',
            )
            .eq('courier_id', widget.courierId)
            .order('created_at', ascending: false)
            .limit(6)
            .catchError((_) => const <Map<String, dynamic>>[]),
        _supabase
            .from('orders')
            .select('created_at, picked_up_at, delivered_at, status')
            .eq('courier_id', widget.courierId)
            .inFilter('status', ['delivered', 'completed', 'auto_completed'])
            .order('updated_at', ascending: false)
            .limit(40)
            .catchError((_) => const <Map<String, dynamic>>[]),
        if (widget.orderId != null && widget.orderId!.trim().isNotEmpty)
          _supabase
              .from('orders')
              .select(
                'id, status, courier_id, delivery_address, created_at, delivered_at, restaurants(name)',
              )
              .eq('id', widget.orderId!)
              .maybeSingle()
              .catchError((_) => null)
        else
          Future.value(null),
        if (widget.orderId != null &&
            widget.orderId!.trim().isNotEmpty &&
            userId != null)
          _supabase
              .from('courier_reviews')
              .select('rating, comment')
              .eq('order_id', widget.orderId!)
              .eq('reviewer_id', userId)
              .maybeSingle()
              .catchError((_) => null)
        else
          Future.value(null),
      ]);

      final reviews = ((results[2] as List?) ?? const [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      final deliveries = ((results[3] as List?) ?? const [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();

      final minutes = <double>[];
      for (final row in deliveries) {
        final deliveredAt = DateTime.tryParse(
          row['delivered_at']?.toString() ?? '',
        );
        final startedAt = DateTime.tryParse(
          row['picked_up_at']?.toString() ??
              row['created_at']?.toString() ??
              '',
        );
        if (deliveredAt != null && startedAt != null) {
          final diff = deliveredAt.difference(startedAt).inMinutes.toDouble();
          if (diff > 0 && diff < 240) {
            minutes.add(diff);
          }
        }
      }

      final positiveCount = reviews.where((row) {
        final rating = (row['rating'] as num?)?.toInt() ?? 0;
        return rating >= 4;
      }).length;
      final orderSummary = (results[4] as Map?)?.cast<String, dynamic>();
      final restaurant = (orderSummary?['restaurants'] as Map?)
          ?.cast<String, dynamic>();
      if (orderSummary != null &&
          (orderSummary['restaurant_name']?.toString().trim().isEmpty ??
              true) &&
          restaurant?['name']?.toString().trim().isNotEmpty == true) {
        orderSummary['restaurant_name'] = restaurant!['name'].toString().trim();
      }
      final existingReview = (results[5] as Map?)?.cast<String, dynamic>();

      if (!mounted) return;
      setState(() {
        _profile = (results[0] as Map?)?.cast<String, dynamic>();
        _courier = (results[1] as Map?)?.cast<String, dynamic>();
        _orderSummary = orderSummary;
        _recentReviews = reviews;
        _existingReview = existingReview;
        _selectedRating = (existingReview?['rating'] as num?)?.toInt() ?? 5;
        _commentController.text = existingReview?['comment']?.toString() ?? '';
        _averageMinutes = minutes.isEmpty
            ? 0
            : minutes.reduce((a, b) => a + b) / minutes.length;
        _satisfactionRate = reviews.isEmpty
            ? 0
            : (positiveCount / reviews.length) * 100;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _submitReview() async {
    final user = _supabase.auth.currentUser;
    final orderId = widget.orderId?.trim() ?? '';
    if (user == null || orderId.isEmpty || !_canReviewOrder) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Este pedido ainda nao esta pronto para avaliacao.'),
        ),
      );
      return;
    }

    setState(() => _isSubmittingReview = true);
    try {
      final response = await _supabase.rpc(
        'submit_courier_review',
        params: {
          'p_order_id': orderId,
          'p_reviewer_id': user.id,
          'p_rating': _selectedRating,
          'p_comment': _commentController.text.trim(),
        },
      );
      if (!mounted) return;
      final success = response is Map && response['success'] == true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? 'Avaliacao enviada com sucesso.'
                : 'Nao foi possivel enviar a avaliacao agora.',
          ),
        ),
      );
      if (success) {
        await _load();
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nao foi possivel enviar a avaliacao agora.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmittingReview = false);
      }
    }
  }

  Future<void> _reportProblem() async {
    final orderId = widget.orderId?.trim() ?? '';
    if (orderId.isEmpty || !_hasLinkedOrder) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nao ha pedido ligado a este perfil.')),
      );
      return;
    }

    final result = await _orderService.reportDeliveryProblem(
      orderId: orderId,
      reason: _commentController.text.trim().isNotEmpty
          ? _commentController.text.trim()
          : 'Cliente reportou um problema a partir do perfil do estafeta.',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.message)));
  }

  Future<void> _shareToChannel(String channel) async {
    final text = '${_shareMessage()}\n\n${_publicCourierLink()}';
    final encodedText = Uri.encodeComponent(text);
    final encodedLink = Uri.encodeComponent(_publicCourierLink());
    Uri? uri;
    switch (channel) {
      case 'whatsapp':
        uri = Uri.parse('https://wa.me/?text=$encodedText');
        break;
      case 'facebook':
        uri = Uri.parse(
          'https://www.facebook.com/sharer/sharer.php?u=$encodedLink',
        );
        break;
      case 'x':
        uri = Uri.parse('https://twitter.com/intent/tweet?text=$encodedText');
        break;
      case 'telegram':
        uri = Uri.parse(
          'https://t.me/share/url?url=$encodedLink&text=$encodedText',
        );
        break;
      case 'instagram':
      case 'tiktok':
        await Clipboard.setData(ClipboardData(text: text));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              channel == 'instagram'
                  ? 'Texto e link copiados para montar o story.'
                  : 'Texto e link copiados para montar o video.',
            ),
          ),
        );
        return;
    }

    if (uri != null) {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) {
        await Clipboard.setData(ClipboardData(text: text));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nao abriu o app externo. Texto copiado.'),
          ),
        );
      }
    }
  }

  Future<void> _saveCardImage() async {
    try {
      final boundary =
          _shareCardKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData?.buffer.asUint8List();
      if (pngBytes == null) return;

      final filename =
          'deligo_courier_${widget.courierId}_${DateTime.now().millisecondsSinceEpoch}.png';
      final savedPath = await savePngBytes(pngBytes, filename);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            savedPath == null
                ? 'No navegador, copie o link ou partilhe pelo WhatsApp.'
                : 'Imagem salva em $savedPath',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nao foi possivel salvar a imagem agora.'),
        ),
      );
    }
  }

  String _shareMessage() {
    final courierName = _courierName;
    final rating = _courierRating;
    final deliveries = _totalDeliveries;
    final phrase = _selectedRating >= 5
        ? 'Mais uma entrega concluida com sucesso.'
        : 'Cliente satisfeito, missao cumprida.';
    return '$phrase\n\n$courierName\n⭐ ${rating > 0 ? rating.toStringAsFixed(1) : 'Novo'}\n🚴 +$deliveries entregas';
  }

  String get _courierName {
    final profileName = _profile?['full_name']?.toString().trim() ?? '';
    if (profileName.isNotEmpty) return profileName;
    final courierName = _courier?['full_name']?.toString().trim() ?? '';
    return courierName.isNotEmpty ? courierName : 'Estafeta DeliGo';
  }

  String get _avatarUrl {
    final profileAvatar = _profile?['avatar_url']?.toString().trim() ?? '';
    if (profileAvatar.isNotEmpty) return profileAvatar;
    return _courier?['avatar_url']?.toString().trim() ?? '';
  }

  double get _courierRating => (_courier?['rating'] as num?)?.toDouble() ?? 0;

  int get _totalDeliveries =>
      (_courier?['total_deliveries'] as num?)?.toInt() ?? 0;

  bool get _isOnline => _courier?['is_online'] == true;

  String _publicCourierLink() {
    return _publicShareService.courierLink(
      widget.courierId,
      orderId: _hasLinkedOrder ? widget.orderId : null,
    );
  }

  bool get _hasLinkedOrder {
    final orderId = widget.orderId?.trim() ?? '';
    final summaryId = _orderSummary?['id']?.toString().trim() ?? '';
    final summaryCourierId =
        _orderSummary?['courier_id']?.toString().trim() ?? '';
    return orderId.isNotEmpty &&
        summaryId == orderId &&
        summaryCourierId == widget.courierId;
  }

  bool get _canReviewOrder {
    if (!_hasLinkedOrder) return false;
    final status = _orderSummary?['status']?.toString().trim() ?? '';
    return status == 'delivered' ||
        status == 'completed' ||
        status == 'auto_completed';
  }

  String _badgeLabel() {
    if (_totalDeliveries >= 10000) return 'Elite';
    if (_totalDeliveries >= 5000) return 'Diamante';
    if (_totalDeliveries >= 1000) return 'Ouro';
    if (_totalDeliveries >= 500) return 'Prata';
    return 'Bronze';
  }

  String _ratingPrompt() {
    switch (_selectedRating) {
      case 1:
      case 2:
        return 'O que deu errado?';
      case 3:
        return 'O que pode melhorar?';
      case 4:
        return 'O que correu bem?';
      default:
        return 'O que voce mais gostou?';
    }
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.of(context).size.width < 380;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('Perfil do estafeta'),
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(16, 12, 16, compact ? 24 : 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeroHeader(compact),
                    const SizedBox(height: 16),
                    _buildMiniProfile(compact),
                    const SizedBox(height: 16),
                    if (_hasLinkedOrder) _buildOrderSummary(compact),
                    if (_hasLinkedOrder) const SizedBox(height: 16),
                    if (widget.orderId != null &&
                        widget.orderId!.trim().isNotEmpty)
                      _buildRatingSection(compact),
                    if (widget.orderId != null &&
                        widget.orderId!.trim().isNotEmpty)
                      const SizedBox(height: 16),
                    _buildShareSection(compact),
                    if (_recentReviews.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _buildRecentReviews(),
                    ],
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildHeroHeader(bool compact) {
    final ratingLabel = _courierRating > 0
        ? _courierRating.toStringAsFixed(1)
        : 'Novo';
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 18 : 22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFE21F2F), Color(0xFFA90717)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: compact ? 38 : 46,
            backgroundColor: Colors.white.withValues(alpha: 0.2),
            backgroundImage: _avatarUrl.isNotEmpty
                ? NetworkImage(_avatarUrl)
                : null,
            child: _avatarUrl.isEmpty
                ? Text(
                    _courierName[0].toUpperCase(),
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 14),
          Text(
            _courierName,
            style: TextStyle(
              fontSize: compact ? 24 : 28,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _heroPill(Icons.star_rounded, '⭐ $ratingLabel'),
              _heroPill(
                Icons.local_shipping_outlined,
                '+$_totalDeliveries entregas',
              ),
              _heroPill(Icons.verified_rounded, _badgeLabel(), highlight: true),
              _heroPill(
                _isOnline ? Icons.circle : Icons.offline_bolt_outlined,
                _isOnline ? 'Online agora' : 'Offline',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniProfile(bool compact) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 16 : 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primaryRed.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Mini perfil do estafeta',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _metricCard(
                'Nota media',
                _courierRating > 0 ? _courierRating.toStringAsFixed(1) : '--',
              ),
              _metricCard('Entregas', '$_totalDeliveries'),
              _metricCard(
                'Tempo medio',
                _averageMinutes > 0 ? '${_averageMinutes.round()} min' : '--',
              ),
              _metricCard(
                'Satisfacao',
                _satisfactionRate > 0 ? '${_satisfactionRate.round()}%' : '--',
              ),
              _metricCard('Nivel', _badgeLabel()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRatingSection(bool compact) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 16 : 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Como foi sua experiencia?',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            _canReviewOrder
                ? _ratingPrompt()
                : 'A avaliacao sera libertada assim que a entrega deste pedido estiver concluida.',
            style: const TextStyle(
              color: AppColors.neutralGray,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 6,
            children: List.generate(5, (index) {
              final filled = index < _selectedRating;
              return IconButton(
                onPressed: () => setState(() => _selectedRating = index + 1),
                icon: Icon(
                  filled ? Icons.star_rounded : Icons.star_border_rounded,
                  color: filled ? Colors.amber : Colors.grey.shade400,
                  size: compact ? 34 : 38,
                ),
              );
            }),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _commentController,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: 'Conta um pouco da tua experiencia com este estafeta',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              filled: true,
              fillColor: const Color(0xFFF8F4EE),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            children: [
              TextButton.icon(
                onPressed: _hasLinkedOrder ? _reportProblem : null,
                icon: const Icon(Icons.flag_outlined),
                label: const Text('Reportar problema'),
              ),
              FilledButton.icon(
                onPressed: _isSubmittingReview || !_canReviewOrder
                    ? null
                    : _submitReview,
                icon: const Icon(Icons.send_rounded),
                label: Text(
                  _existingReview == null
                      ? 'Enviar avaliacao'
                      : 'Atualizar avaliacao',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOrderSummary(bool compact) {
    final restaurantName = (() {
      final direct = _orderSummary?['restaurant_name']?.toString().trim() ?? '';
      if (direct.isNotEmpty) return direct;
      final nested =
          (_orderSummary?['restaurants'] as Map?)?['name']?.toString().trim() ??
          '';
      return nested.isNotEmpty ? nested : 'Restaurante';
    })();
    final deliveryAddress = LocationDisplay.displayAddress(
      address: _orderSummary?['delivery_address']?.toString().trim(),
      fallback: 'Endereco do cliente confirmado no mapa',
    );
    final status = _orderSummary?['status']?.toString().trim() ?? '';
    final deliveredAt = DateTime.tryParse(
      _orderSummary?['delivered_at']?.toString() ?? '',
    )?.toLocal();

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 16 : 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Resumo da entrega',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          Text(
            restaurantName,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          if (deliveryAddress.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              deliveryAddress,
              style: const TextStyle(
                color: AppColors.neutralGray,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _metricCard('Estado', status.isNotEmpty ? status : '--'),
              _metricCard(
                'Concluida',
                deliveredAt != null
                    ? '${deliveredAt.hour.toString().padLeft(2, '0')}:${deliveredAt.minute.toString().padLeft(2, '0')}'
                    : '--',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildShareSection(bool compact) {
    final shareLink = _publicCourierLink();
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 16 : 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Cartao compartilhavel',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F4EE),
                borderRadius: BorderRadius.circular(20),
              ),
              child: QrImageView(
                data: shareLink,
                version: QrVersions.auto,
                size: compact ? 132 : 156,
                backgroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 10),
          SelectableText(
            shareLink,
            style: const TextStyle(
              color: AppColors.neutralGray,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          RepaintBoundary(
            key: _shareCardKey,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFF0D6), Color(0xFFFFD8A8)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundImage: _avatarUrl.isNotEmpty
                            ? NetworkImage(_avatarUrl)
                            : null,
                        child: _avatarUrl.isEmpty
                            ? Text(_courierName[0].toUpperCase())
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _courierName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              '⭐ ${_courierRating > 0 ? _courierRating.toStringAsFixed(1) : 'Novo'} • +$_totalDeliveries entregas',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _shareMessage(),
                    style: const TextStyle(
                      fontSize: 16,
                      height: 1.35,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _shareToChannel('whatsapp'),
                icon: const Icon(Icons.share_outlined),
                label: const Text('Compartilhar no WhatsApp'),
              ),
              OutlinedButton.icon(
                onPressed: () => _shareToChannel('instagram'),
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('Compartilhar no Instagram'),
              ),
              PopupMenuButton<String>(
                tooltip: 'Mais redes sociais',
                onSelected: _shareToChannel,
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'facebook', child: Text('Facebook')),
                  PopupMenuItem(value: 'x', child: Text('X')),
                  PopupMenuItem(value: 'telegram', child: Text('Telegram')),
                  PopupMenuItem(value: 'tiktok', child: Text('TikTok')),
                ],
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.ios_share_rounded),
                      SizedBox(width: 8),
                      Text('Mais redes'),
                    ],
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: _saveCardImage,
                icon: const Icon(Icons.download_outlined),
                label: const Text('Salvar imagem'),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: shareLink));
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Link do estafeta copiado.')),
                  );
                },
                icon: const Icon(Icons.link_outlined),
                label: const Text('Copiar link'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRecentReviews() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Historico de avaliacoes',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          ..._recentReviews.map((review) {
            final rating = (review['rating'] as num?)?.toInt() ?? 5;
            final comment = review['comment']?.toString().trim() ?? '';
            final reviewer = review['reviewer_name']?.toString().trim();
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F7F7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          reviewer?.isNotEmpty == true
                              ? reviewer!
                              : 'Cliente DeliGo',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const Spacer(),
                        Text('⭐ $rating'),
                      ],
                    ),
                    if (comment.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        comment,
                        style: const TextStyle(
                          color: AppColors.neutralGray,
                          height: 1.35,
                        ),
                      ),
                    ],
                    if ((review['id']?.toString() ?? '').isNotEmpty)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () =>
                              context.push('/review/courier/${review['id']}'),
                          icon: const Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 17,
                          ),
                          label: const Text('Gostar ou responder'),
                        ),
                      ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _heroPill(IconData icon, String label, {bool highlight = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: highlight
            ? const Color(0xFFFFE5AE)
            : Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 15,
            color: highlight ? const Color(0xFF6C4B00) : Colors.white,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: highlight ? const Color(0xFF6C4B00) : Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricCard(String label, String value) {
    return Container(
      width: 148,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primaryRed.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primaryRed.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: AppColors.primaryRed,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.neutralGray,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
