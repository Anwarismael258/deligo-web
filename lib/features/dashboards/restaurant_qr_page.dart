import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../config/theme/app_colors.dart';
import '../../shared/models/menu_item.dart';
import '../../shared/platform/share_card_saver.dart';
import '../../services/public_share_service.dart';

class RestaurantQrPage extends StatefulWidget {
  final String restaurantId;
  final String restaurantName;
  final String imageUrl;
  final List<MenuItem> dishes;

  const RestaurantQrPage({
    super.key,
    required this.restaurantId,
    required this.restaurantName,
    required this.imageUrl,
    this.dishes = const [],
  });

  @override
  State<RestaurantQrPage> createState() => _RestaurantQrPageState();
}

class _RestaurantQrPageState extends State<RestaurantQrPage> {
  final _posterKey = GlobalKey();
  bool _busy = false;

  String get _link =>
      PublicShareService.instance.restaurantLink(widget.restaurantId);

  String get _fileName {
    final safe = widget.restaurantName
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9À-ÿ]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return 'DeliGo_${safe.isEmpty ? 'Restaurante' : safe}_QR.png';
  }

  Future<Uint8List?> _renderPoster() async {
    await Future<void>.delayed(const Duration(milliseconds: 180));
    final boundary =
        _posterKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    // 794x1123 logical pixels rendered at 2x = 1588x2246 PNG (A4 portrait).
    final image = await boundary.toImage(pixelRatio: 2.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  }

  Future<void> _export({required bool share}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await _renderPoster();
      if (bytes == null || !mounted) return;
      final path = await savePngBytes(bytes, _fileName);
      if (share && path != null) {
        await Share.shareXFiles([
          XFile(path),
        ], text: 'PEÇA PELO DELIGO\n$_link');
      }
      if (!share && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cartaz pronto para imprimir.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dishes = widget.dishes
        .where((d) => (d.imageUrl ?? '').isNotEmpty)
        .take(3)
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('QR Code do restaurante')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Text(
                'Divulgue o seu restaurante e facilite os pedidos pelo DeliGo.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FittedBox(
                fit: BoxFit.contain,
                child: SizedBox(
                  width: 794,
                  height: 1123,
                  child: RepaintBoundary(
                    key: _posterKey,
                    child: _Poster(
                      name: widget.restaurantName,
                      imageUrl: widget.imageUrl,
                      link: _link,
                      dishes: dishes,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy ? null : () => _export(share: false),
                  icon: const Icon(Icons.print_outlined),
                  label: Text(_busy ? 'A preparar...' : 'Baixar para imprimir'),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : () => _export(share: true),
                      icon: const Icon(Icons.share_outlined),
                      label: const Text('Partilhar'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: _link));
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Link copiado.')),
                          );
                        }
                      },
                      icon: const Icon(Icons.link),
                      label: const Text('Copiar link'),
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
}

class _Poster extends StatelessWidget {
  final String name;
  final String imageUrl;
  final String link;
  final List<MenuItem> dishes;
  const _Poster({
    required this.name,
    required this.imageUrl,
    required this.link,
    required this.dishes,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: 794,
    height: 1123,
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFFFFBF6), Color(0xFFFFE9D8), Color(0xFFE53935)],
      ),
    ),
    child: Stack(
      children: [
        Positioned.fill(
          child: Opacity(
            opacity: .24,
            child: Image.network(
              imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Image.asset(
                'assets/deligo_official_poster.png',
                fit: BoxFit.cover,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(42, 34, 42, 34),
          child: Column(
            children: [
              const _DeligoBrand(),
              const SizedBox(height: 32),
              const Text(
                'PEÇA PELO',
                style: TextStyle(
                  fontSize: 54,
                  height: .95,
                  fontWeight: FontWeight.w900,
                  color: Colors.black,
                ),
              ),
              const Text(
                'DELIGO',
                style: TextStyle(
                  fontSize: 76,
                  height: .95,
                  fontWeight: FontWeight.w900,
                  color: AppColors.primaryRed,
                ),
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFA726),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 27,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Container(
                padding: const EdgeInsets.all(26),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 18,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    QrImageView(
                      data: link,
                      size: 330,
                      backgroundColor: Colors.white,
                      padding: const EdgeInsets.all(12),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Escaneie para ver\no nosso menu.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 28,
                        height: 1.05,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (dishes.isNotEmpty) _DishStrip(dishes: dishes),
              const SizedBox(height: 18),
              const Text(
                'Menu completo  •  Entrega rápida  •  Pagamento seguro',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 20),
              const _DeligoBrand(light: true),
            ],
          ),
        ),
      ],
    ),
  );
}

class _DeligoBrand extends StatelessWidget {
  final bool light;
  const _DeligoBrand({this.light = false});
  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Icon(
        Icons.restaurant_menu_rounded,
        size: 46,
        color: light ? Colors.white : AppColors.primaryRed,
      ),
      const SizedBox(width: 10),
      Text(
        'DeliGo',
        style: TextStyle(
          fontSize: 42,
          fontWeight: FontWeight.w900,
          color: light ? Colors.white : Colors.black,
        ),
      ),
    ],
  );
}

class _DishStrip extends StatelessWidget {
  final List<MenuItem> dishes;
  const _DishStrip({required this.dishes});
  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: dishes
        .map(
          (dish) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                dish.imageUrl!,
                width: 150,
                height: 92,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 150,
                  height: 92,
                  color: Colors.white70,
                  child: const Icon(Icons.fastfood_outlined, size: 32),
                ),
              ),
            ),
          ),
        )
        .toList(),
  );
}
