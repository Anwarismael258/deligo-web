import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/theme/app_colors.dart';
import '../../services/image_service.dart';
import '../../services/order_service.dart';
import '../../services/public_share_service.dart';
import '../../services/restaurant_service.dart';
import '../../shared/platform/share_card_saver.dart';
import '../../shared/models/menu_item.dart';
import '../../shared/models/restaurant.dart';
import '../../shared/utils/location_display.dart';

class RestaurantPublicPage extends StatefulWidget {
  final String restaurantId;
  final String? orderId;

  const RestaurantPublicPage({
    super.key,
    required this.restaurantId,
    this.orderId,
  });

  @override
  State<RestaurantPublicPage> createState() => _RestaurantPublicPageState();
}

class _RestaurantPublicPageState extends State<RestaurantPublicPage> {
  final _supabase = Supabase.instance.client;
  final _restaurantService = RestaurantService();
  final _orderService = OrderService();
  final _publicShare = PublicShareService.instance;
  final _imageService = ImageService();
  final _commentController = TextEditingController();
  final _shareCardKey = GlobalKey();

  Restaurant? _restaurant;
  Map<String, dynamic>? _orderSummary;
  Map<String, dynamic>? _existingReview;
  List<Map<String, dynamic>> _reviews = const [];
  List<MenuItem> _menuItems = const [];
  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _isUploadingImage = false;
  String? _loadError;
  int _overallRating = 5;
  int _foodRating = 5;
  int _packagingRating = 5;
  int _preparationRating = 5;
  int _serviceRating = 5;
  int _completedOrdersCount = 0;
  double _satisfactionRate = 0;
  String? _reviewImageUrl;

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

  bool get _hasLinkedOrder {
    final orderId = widget.orderId?.trim() ?? '';
    return orderId.isNotEmpty &&
        _orderSummary?['id']?.toString() == orderId &&
        _orderSummary?['restaurant_id']?.toString() == widget.restaurantId;
  }

  bool get _canReviewOrder {
    if (!_hasLinkedOrder) return false;
    final status = _orderSummary?['status']?.toString() ?? '';
    return status == 'completed' ||
        status == 'auto_completed' ||
        status == 'delivered';
  }

  String get _shareLink => _publicShare.restaurantLink(
    widget.restaurantId,
    orderId: _hasLinkedOrder ? widget.orderId : null,
  );

  List<MenuItem> get _topDishes {
    final ranked = List<MenuItem>.from(_menuItems)
      ..sort((a, b) => b.rating.compareTo(a.rating));
    return ranked.take(3).toList();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      final results = await Future.wait<dynamic>([
        _restaurantService.getPublicRestaurantById(widget.restaurantId),
        _restaurantService.getMenuItems(widget.restaurantId),
        _safeReviews(),
        _safeCompletedOrders(),
        widget.orderId != null && widget.orderId!.trim().isNotEmpty
            ? _supabase
                  .from('orders')
                  .select('id, status, restaurant_id, delivery_address')
                  .eq('id', widget.orderId!)
                  .maybeSingle()
            : Future.value(null),
        widget.orderId != null &&
                widget.orderId!.trim().isNotEmpty &&
                userId != null
            ? _supabase
                  .from('reviews')
                  .select(
                    'rating, comment, image_url, food_rating, packaging_rating, preparation_rating, service_rating',
                  )
                  .eq('order_id', widget.orderId!)
                  .eq('reviewer_id', userId)
                  .maybeSingle()
            : Future.value(null),
      ]);

      final reviews = ((results[2] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final positive = reviews.where((e) {
        final rating = (e['rating'] as num?)?.toInt() ?? 0;
        return rating >= 4;
      }).length;
      final existing = (results[5] as Map?)?.cast<String, dynamic>();

      if (!mounted) return;
      setState(() {
        _loadError = null;
        _restaurant = results[0] as Restaurant?;
        _menuItems = (results[1] as List).cast<MenuItem>();
        _reviews = reviews;
        _completedOrdersCount = ((results[3] as List?) ?? const []).length;
        _orderSummary = (results[4] as Map?)?.cast<String, dynamic>();
        _existingReview = existing;
        _overallRating = (existing?['rating'] as num?)?.toInt() ?? 5;
        _foodRating = (existing?['food_rating'] as num?)?.toInt() ?? 5;
        _packagingRating =
            (existing?['packaging_rating'] as num?)?.toInt() ?? 5;
        _preparationRating =
            (existing?['preparation_rating'] as num?)?.toInt() ?? 5;
        _serviceRating = (existing?['service_rating'] as num?)?.toInt() ?? 5;
        _reviewImageUrl = existing?['image_url']?.toString();
        _commentController.text = existing?['comment']?.toString() ?? '';
        _satisfactionRate = reviews.isEmpty
            ? 0
            : (positive / reviews.length) * 100;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error.toString();
        _isLoading = false;
      });
    }
  }

  Future<List<Map<String, dynamic>>> _safeReviews() async {
    try {
      final rows = await _supabase
          .from('reviews')
          .select('reviewer_name, rating, comment, image_url, created_at')
          .eq('restaurant_id', widget.restaurantId)
          .order('created_at', ascending: false)
          .limit(12);
      return (rows as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<Map<String, dynamic>>> _safeCompletedOrders() async {
    try {
      final rows = await _supabase
          .from('orders')
          .select('id')
          .eq('restaurant_id', widget.restaurantId)
          .inFilter('status', ['delivered', 'completed', 'auto_completed']);
      return (rows as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _pickReviewPhoto() async {
    setState(() => _isUploadingImage = true);
    final url = await _imageService.uploadImageFromSource(
      'chat-attachments',
      'restaurant_reviews/${widget.restaurantId}',
      ImageSource.gallery,
    );
    if (!mounted) return;
    setState(() {
      _reviewImageUrl = url;
      _isUploadingImage = false;
    });
  }

  Future<void> _submitReview() async {
    final user = _supabase.auth.currentUser;
    final orderId = widget.orderId?.trim() ?? '';
    if (user == null || orderId.isEmpty || !_canReviewOrder) return;
    setState(() => _isSubmitting = true);
    try {
      final response = await _supabase.rpc(
        'submit_restaurant_review',
        params: {
          'p_order_id': orderId,
          'p_reviewer_id': user.id,
          'p_rating': _overallRating,
          'p_comment': _commentController.text.trim(),
          'p_food_rating': _foodRating,
          'p_packaging_rating': _packagingRating,
          'p_preparation_rating': _preparationRating,
          'p_service_rating': _serviceRating,
          'p_image_url': _reviewImageUrl,
        },
      );
      if (!mounted) return;
      final success = response is Map && response['success'] == true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? 'Avaliacao do restaurante enviada com sucesso.'
                : 'Nao foi possivel enviar a avaliacao agora.',
          ),
        ),
      );
      if (success) {
        await _load();
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _reportProblem() async {
    final orderId = widget.orderId?.trim() ?? '';
    if (orderId.isEmpty || !_hasLinkedOrder) return;
    final ok = await _orderService.openOrderDispute(
      orderId: orderId,
      disputeType: 'restaurant_review_issue',
      reason: _commentController.text.trim().isNotEmpty
          ? _commentController.text.trim()
          : 'Cliente reportou um problema a partir do perfil do restaurante.',
      openedByRole: 'client',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Problema reportado para analise.'
              : 'Nao foi possivel reportar o problema agora.',
        ),
      ),
    );
  }

  Future<void> _shareToChannel(String channel) async {
    final text =
        'Veja o perfil do restaurante ${_restaurant?.name ?? 'DeliGo'}.\n$_shareLink';
    Uri? uri;
    if (channel == 'whatsapp') {
      uri = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}');
    } else {
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Texto copiado para montar o story.')),
      );
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _saveCardImage() async {
    final boundary =
        _shareCardKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) return;
    final image = await boundary.toImage(pixelRatio: 3);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final png = bytes?.buffer.asUint8List();
    if (png == null) return;
    final savedPath = await savePngBytes(
      png,
      'restaurant_review_${DateTime.now().millisecondsSinceEpoch}.png',
    );
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
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.of(context).size.width < 380;
    final restaurant = _restaurant;
    final topDish = _topDishes.isEmpty ? '--' : _topDishes.first.name;
    final ratingLabel = (restaurant?.rating ?? 0) > 0
        ? restaurant!.rating!.toStringAsFixed(1)
        : 'Novo';

    return Scaffold(
      backgroundColor: const Color(0xFFF7F1E8),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF7F1E8),
        elevation: 0,
        title: const Text('Perfil do restaurante'),
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _restaurant == null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.restaurant_outlined, size: 48),
                      const SizedBox(height: 12),
                      Text(
                        _loadError == null
                            ? 'Restaurante não encontrado.'
                            : 'Não foi possível carregar este restaurante.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Tentar novamente'),
                      ),
                    ],
                  ),
                ),
              )
            : SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(16, 12, 16, compact ? 24 : 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _panel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (restaurant?.imageUrl?.trim().isNotEmpty == true)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(18),
                              child: AspectRatio(
                                aspectRatio: 16 / 9,
                                child: CachedNetworkImage(
                                  imageUrl: restaurant!.imageUrl!,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, __, ___) => Container(
                                    color: const Color(0xFFEADFD2),
                                    child: const Icon(
                                      Icons.restaurant_rounded,
                                      size: 48,
                                      color: Color(0xFF8D6E63),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          const SizedBox(height: 10),
                          Text(
                            restaurant?.name ?? 'Restaurante DeliGo',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 22,
                              height: 1.15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _pill('Nota $ratingLabel'),
                              _pill('${_reviews.length} avaliacoes'),
                              _pill(
                                '${restaurant?.deliveryTime ?? 25}-${(restaurant?.deliveryTime ?? 25) + 10} min',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _panel(
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _metric(
                            'Pedidos concluidos',
                            '$_completedOrdersCount',
                          ),
                          _metric(
                            'Satisfacao',
                            _satisfactionRate > 0
                                ? '${_satisfactionRate.round()}%'
                                : '--',
                          ),
                          _metric('Top prato', topDish),
                          _metric('Endereco', restaurant?.address ?? '--'),
                        ],
                      ),
                    ),
                    if (_hasLinkedOrder) ...[
                      const SizedBox(height: 16),
                      _panel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Resumo do pedido',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text('Estado: ${_orderSummary?['status'] ?? '--'}'),
                            const SizedBox(height: 4),
                            Text(
                              LocationDisplay.displayAddress(
                                address: _orderSummary?['delivery_address']
                                    ?.toString(),
                                fallback: 'Endereco confirmado no mapa',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (widget.orderId != null &&
                        widget.orderId!.trim().isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _buildReviewPanel(),
                    ],
                    const SizedBox(height: 16),
                    _buildSharePanel(compact),
                    if (_reviews.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _buildRecentReviews(),
                    ],
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildReviewPanel() {
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Como foi sua experiencia com o restaurante?',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            _overallRating >= 5
                ? 'O que voce mais gostou?'
                : _overallRating <= 2
                ? 'O que podemos melhorar?'
                : 'Conta-nos como foi o pedido.',
            style: const TextStyle(color: AppColors.neutralGray),
          ),
          const SizedBox(height: 12),
          _stars('Avaliacao geral', _overallRating, (v) => _overallRating = v),
          _stars('Comida', _foodRating, (v) => _foodRating = v),
          _stars('Embalagem', _packagingRating, (v) => _packagingRating = v),
          _stars(
            'Tempo de preparo',
            _preparationRating,
            (v) => _preparationRating = v,
          ),
          _stars('Atendimento', _serviceRating, (v) => _serviceRating = v),
          const SizedBox(height: 10),
          TextField(
            controller: _commentController,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: 'Escreve o teu comentario',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              filled: true,
              fillColor: const Color(0xFFF8F4EE),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _canReviewOrder && !_isUploadingImage
                    ? _pickReviewPhoto
                    : null,
                icon: const Icon(Icons.photo_camera_back_outlined),
                label: Text(
                  _reviewImageUrl == null ? 'Adicionar foto' : 'Trocar foto',
                ),
              ),
              TextButton.icon(
                onPressed: _hasLinkedOrder ? _reportProblem : null,
                icon: const Icon(Icons.flag_outlined),
                label: const Text('Reportar problema'),
              ),
              FilledButton.icon(
                onPressed: _isSubmitting || !_canReviewOrder
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

  Widget _buildSharePanel(bool compact) {
    final shareText =
        '${_restaurant?.name ?? 'Restaurante'}\nNota ${(_restaurant?.rating ?? 0) > 0 ? _restaurant!.rating!.toStringAsFixed(1) : 'Novo'}\n$_shareLink';
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Card para redes sociais',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          Center(
            child: QrImageView(
              data: _shareLink,
              version: QrVersions.auto,
              size: compact ? 132 : 156,
              backgroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          SelectableText(
            _shareLink,
            style: const TextStyle(color: AppColors.neutralGray),
          ),
          const SizedBox(height: 12),
          RepaintBoundary(
            key: _shareCardKey,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFF0D6), Color(0xFFFFD5B8)],
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Text(
                _commentController.text.trim().isNotEmpty
                    ? _commentController.text.trim()
                    : shareText,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
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
              FilledButton.icon(
                onPressed: _saveCardImage,
                icon: const Icon(Icons.download_outlined),
                label: const Text('Salvar imagem'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRecentReviews() {
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Avaliacoes recentes',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          ..._reviews.take(5).map((review) {
            final imageUrl = review['image_url']?.toString().trim() ?? '';
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F4EE),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      review['reviewer_name']?.toString() ?? 'Cliente DeliGo',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text('⭐ ${(review['rating'] as num?)?.toInt() ?? 5}'),
                    if ((review['comment']?.toString().trim().isNotEmpty ??
                        false)) ...[
                      const SizedBox(height: 6),
                      Text(
                        review['comment'].toString(),
                        style: const TextStyle(color: AppColors.neutralGray),
                      ),
                    ],
                    if (imageUrl.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: CachedNetworkImage(
                          imageUrl: imageUrl,
                          height: 140,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _stars(String label, int value, ValueChanged<int> update) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        ...List.generate(5, (index) {
          final filled = index < value;
          return IconButton(
            onPressed: _canReviewOrder
                ? () => setState(() => update(index + 1))
                : null,
            icon: Icon(
              filled ? Icons.star_rounded : Icons.star_border_rounded,
              color: filled ? Colors.amber : Colors.grey.shade400,
            ),
          );
        }),
      ],
    );
  }

  Widget _pill(String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: const Color(0xFFF8F4EE),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
  );

  Widget _metric(String label, String value) => Container(
    width: 150,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFF8F4EE),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: AppColors.neutralGray)),
      ],
    ),
  );

  Widget _panel({required Widget child}) => Container(
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
    child: child,
  );
}
