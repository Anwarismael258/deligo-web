import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class OfficialHomePage extends StatefulWidget {
  const OfficialHomePage({super.key});

  @override
  State<OfficialHomePage> createState() => _OfficialHomePageState();
}

class _OfficialHomePageState extends State<OfficialHomePage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070B12),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _HeroSection(controller: _controller)),
          const SliverToBoxAdapter(child: _AudienceSection()),
          const SliverToBoxAdapter(child: _SeoSection()),
          const SliverToBoxAdapter(child: _FinalCtaSection()),
        ],
      ),
    );
  }
}

class _HeroSection extends StatelessWidget {
  const _HeroSection({required this.controller});

  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isCompact = size.width < 760;
    final minHeight = isCompact ? 820.0 : math.max(720.0, size.height * 0.92);

    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight),
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/marketing/maputo-deligo-hero.png',
              fit: BoxFit.cover,
              alignment: isCompact ? Alignment.center : Alignment.centerRight,
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    const Color(0xFF05070B),
                    const Color(0xFF05070B).withValues(alpha: 0.74),
                    const Color(
                      0xFF05070B,
                    ).withValues(alpha: isCompact ? 0.48 : 0.18),
                  ],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: AnimatedBuilder(
              animation: controller,
              builder: (context, _) => CustomPaint(
                painter: _DeliveryLightsPainter(controller.value),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isCompact ? 20 : 34,
                vertical: 26,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _TopBar(isCompact: isCompact),
                  SizedBox(height: isCompact ? 58 : 86),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: isCompact ? size.width - 40 : 560,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _LivePill(text: 'Entrega rapida em Maputo'),
                        const SizedBox(height: 22),
                        Text(
                          'Maputo nunca para. Nos tambem nao.',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: isCompact ? 42 : 62,
                            height: 1.02,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Peça comida online, acompanhe em tempo real e conecte clientes, restaurantes e estafetas numa unica plataforma.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.78),
                            fontSize: isCompact ? 17 : 20,
                            height: 1.55,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 28),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            _ActionButton(
                              label: 'Pedir Agora',
                              icon: Icons.shopping_bag_rounded,
                              filled: true,
                              onTap: () => context.go('/client-dashboard'),
                            ),
                            _ActionButton(
                              label: 'Cadastrar Restaurante',
                              icon: Icons.storefront_rounded,
                              onTap: () => context.go('/register'),
                            ),
                            _ActionButton(
                              label: 'Ser Estafeta',
                              icon: Icons.delivery_dining_rounded,
                              onTap: () => context.go('/register'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Padding(
                    padding: EdgeInsets.only(
                      top: isCompact ? 52 : 72,
                      bottom: isCompact ? 22 : 10,
                    ),
                    child: _HeroMetrics(isCompact: isCompact),
                  ),
                ],
              ),
            ),
          ),
          if (!isCompact)
            const Positioned(right: 32, top: 122, child: _OrderTimeline()),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.isCompact});

  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        RichText(
          text: const TextSpan(
            style: TextStyle(fontSize: 38, fontWeight: FontWeight.w900),
            children: [
              TextSpan(
                text: 'Deli',
                style: TextStyle(color: Colors.white),
              ),
              TextSpan(
                text: 'Go',
                style: TextStyle(color: Color(0xFFFF1F2E)),
              ),
            ],
          ),
        ),
        const Spacer(),
        if (!isCompact) ...[
          _NavLink(
            label: 'Como funciona',
            onTap: () => context.go('/delivery-maputo'),
          ),
          _NavLink(label: 'Restaurantes', onTap: () => context.go('/register')),
          _NavLink(label: 'Entrar', onTap: () => context.go('/app')),
        ],
        const SizedBox(width: 12),
        _ActionButton(
          label: isCompact ? 'App' : 'Abrir App',
          icon: Icons.login_rounded,
          compact: true,
          onTap: () => context.go('/app'),
        ),
      ],
    );
  }
}

class _NavLink extends StatelessWidget {
  const _NavLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.78),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _LivePill extends StatelessWidget {
  const _LivePill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Color(0xFF22C55E),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 9),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.filled = false,
    this.compact = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool filled;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: compact ? 44 : 52,
      child: FilledButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: compact ? 18 : 20),
        label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: filled
              ? const Color(0xFFE91C25)
              : Colors.white.withValues(alpha: 0.09),
          foregroundColor: Colors.white,
          padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color: filled
                  ? const Color(0xFFE91C25)
                  : Colors.white.withValues(alpha: 0.22),
            ),
          ),
          textStyle: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: compact ? 14 : 15,
          ),
        ),
      ),
    );
  }
}

class _HeroMetrics extends StatelessWidget {
  const _HeroMetrics({required this.isCompact});

  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    final metrics = [
      (
        'Pedidos ativos',
        '128',
        Icons.shopping_bag_rounded,
        const Color(0xFFFF2431),
      ),
      (
        'Entregas hoje',
        '1.247',
        Icons.verified_rounded,
        const Color(0xFF22C55E),
      ),
      (
        'Restaurantes ativos',
        '86',
        Icons.storefront_rounded,
        const Color(0xFFFBBF24),
      ),
      (
        'Estafetas online',
        '312',
        Icons.delivery_dining_rounded,
        const Color(0xFF38BDF8),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = isCompact ? constraints.maxWidth : 218.0;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: metrics
              .map(
                (metric) => SizedBox(
                  width: width,
                  child: _MetricTile(
                    label: metric.$1,
                    value: metric.$2,
                    icon: metric.$3,
                    color: metric.$4,
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF07101D).withValues(alpha: 0.74),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.82),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderTimeline extends StatelessWidget {
  const _OrderTimeline();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 330,
      child: Column(
        children: const [
          _TimelineTile(
            icon: Icons.shopping_bag_rounded,
            title: 'Cliente fez o pedido',
            subtitle: 'Polana, Maputo',
            color: Color(0xFFFF2431),
          ),
          SizedBox(height: 12),
          _TimelineTile(
            icon: Icons.storefront_rounded,
            title: 'Restaurante recebeu',
            subtitle: 'Kudu Burger',
            color: Color(0xFFFBBF24),
          ),
          SizedBox(height: 12),
          _TimelineTile(
            icon: Icons.delivery_dining_rounded,
            title: 'Estafeta a caminho',
            subtitle: 'Honda CG 125',
            color: Color(0xFF22C55E),
          ),
        ],
      ),
    );
  }
}

class _TimelineTile extends StatelessWidget {
  const _TimelineTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF05070B).withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  subtitle,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.72)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AudienceSection extends StatelessWidget {
  const _AudienceSection();

  @override
  Widget build(BuildContext context) {
    return _SectionShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            eyebrow: 'Uma plataforma, tres movimentos',
            title: 'Cliente pede. Restaurante prepara. Estafeta entrega.',
            subtitle:
                'A DeliGo junta o pedido online, o painel no computador e o acompanhamento da entrega em tempo real.',
          ),
          const SizedBox(height: 26),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 860;
              final width = compact
                  ? constraints.maxWidth
                  : (constraints.maxWidth - 32) / 3;
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  _AudienceCard(
                    width: width,
                    icon: Icons.phone_iphone_rounded,
                    title: 'Clientes pedem sem instalar',
                    body:
                        'A pessoa encontra a DeliGo no Google, abre no navegador e faz o pedido pelo web app.',
                  ),
                  _AudienceCard(
                    width: width,
                    icon: Icons.desktop_windows_rounded,
                    title: 'Restaurantes trabalham no computador',
                    body:
                        'Pedidos, pratos, status, vendas e carteira ficam num painel claro para operar todos os dias.',
                  ),
                  _AudienceCard(
                    width: width,
                    icon: Icons.route_rounded,
                    title: 'Estafetas acompanham online',
                    body:
                        'Disponibilidade, entregas aceites, rotas e ganhos aparecem numa experiencia rapida.',
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _AudienceCard extends StatelessWidget {
  const _AudienceCard({
    required this.width,
    required this.icon,
    required this.title,
    required this.body,
  });

  final double width;
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: const Color(0xFFE91C25), size: 34),
            const SizedBox(height: 18),
            Text(
              title,
              style: const TextStyle(
                color: Color(0xFF121722),
                fontSize: 22,
                height: 1.15,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              body,
              style: const TextStyle(
                color: Color(0xFF566070),
                fontSize: 15,
                height: 1.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SeoSection extends StatelessWidget {
  const _SeoSection();

  @override
  Widget build(BuildContext context) {
    return _SectionShell(
      dark: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            eyebrow: 'Google encontra a DeliGo',
            title: 'Paginas preparadas para delivery em Maputo.',
            subtitle:
                'A homepage ja fala a lingua que clientes pesquisam: delivery, restaurantes, comida online, pedidos e entrega rapida em Maputo.',
            dark: true,
          ),
          const SizedBox(height: 22),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: const [
              _SearchChip('delivery em Maputo'),
              _SearchChip('pedir comida online'),
              _SearchChip('restaurantes em Maputo'),
              _SearchChip('pizza delivery Maputo'),
              _SearchChip('trabalhar como estafeta'),
              _SearchChip('cadastrar restaurante'),
            ],
          ),
        ],
      ),
    );
  }
}

class _SearchChip extends StatelessWidget {
  const _SearchChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _FinalCtaSection extends StatelessWidget {
  const _FinalCtaSection();

  @override
  Widget build(BuildContext context) {
    return _SectionShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            eyebrow: 'DeliGo oficial',
            title: 'Comece pelo site. Continue no app.',
            subtitle:
                'A primeira versao ja posiciona a marca, abre caminho para SEO e leva clientes, restaurantes e estafetas para as areas certas.',
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _ActionButton(
                label: 'Pedir Agora',
                icon: Icons.shopping_bag_rounded,
                filled: true,
                onTap: () => context.go('/client-dashboard'),
              ),
              _ActionButton(
                label: 'Abrir o App',
                icon: Icons.login_rounded,
                onTap: () => context.go('/app'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionShell extends StatelessWidget {
  const _SectionShell({required this.child, this.dark = false});

  final Widget child;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: dark ? const Color(0xFF0B111C) : const Color(0xFFF6F7F9),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 72),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    this.dark = false,
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            eyebrow.toUpperCase(),
            style: const TextStyle(
              color: Color(0xFFE91C25),
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: TextStyle(
              color: dark ? Colors.white : const Color(0xFF111827),
              fontSize: 38,
              height: 1.08,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            subtitle,
            style: TextStyle(
              color: dark
                  ? Colors.white.withValues(alpha: 0.74)
                  : const Color(0xFF566070),
              fontSize: 17,
              height: 1.55,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _DeliveryLightsPainter extends CustomPainter {
  _DeliveryLightsPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final redPath = Path()
      ..moveTo(size.width * 0.18, size.height * 0.86)
      ..cubicTo(
        size.width * 0.28,
        size.height * 0.66,
        size.width * 0.20,
        size.height * 0.48,
        size.width * 0.42,
        size.height * 0.36,
      );
    final yellowPath = Path()
      ..moveTo(size.width * 0.54, size.height * 0.74)
      ..cubicTo(
        size.width * 0.68,
        size.height * 0.58,
        size.width * 0.62,
        size.height * 0.44,
        size.width * 0.84,
        size.height * 0.34,
      );

    _drawRoute(canvas, redPath, const Color(0xFFFF2633), progress);
    _drawRoute(
      canvas,
      yellowPath,
      const Color(0xFFFFB21A),
      (progress + 0.35) % 1,
    );
  }

  void _drawRoute(Canvas canvas, Path path, Color color, double routeProgress) {
    final metric = path.computeMetrics().first;
    final length = metric.length;
    final start = (length * routeProgress) - 130;
    final end = length * routeProgress;
    final visible = metric.extractPath(math.max(0, start), math.max(0, end));
    final glow = Paint()
      ..color = color.withValues(alpha: 0.30)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;
    final line = Paint()
      ..color = color.withValues(alpha: 0.78)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(visible, glow);
    canvas.drawPath(visible, line);
  }

  @override
  bool shouldRepaint(covariant _DeliveryLightsPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
