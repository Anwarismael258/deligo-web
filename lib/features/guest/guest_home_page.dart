import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/restaurant_service.dart';
import '../categories/deligo_food_categories.dart';
import '../../shared/models/menu_item.dart';
import '../../shared/models/restaurant.dart';

class GuestHomePage extends StatefulWidget {
  const GuestHomePage({super.key});

  @override
  State<GuestHomePage> createState() => _GuestHomePageState();
}

class _GuestHomePageState extends State<GuestHomePage> {
  final _searchController = TextEditingController();
  final _restaurantService = RestaurantService();
  late Future<List<Restaurant>> _restaurantsFuture;
  late Future<List<MenuItem>> _featuredDishesFuture;
  final _heroController = PageController();
  Timer? _heroTimer;
  int _heroIndex = 0;
  String _selectedCategory = 'Todos';
  static const _categories = [
    'Todos',
    'Local',
    'Carnes',
    'Mariscos',
    'Fast Food',
    'Saudável',
    'Lanches',
    'Bebidas',
  ];

  @override
  void initState() {
    super.initState();
    _restaurantsFuture = _loadRestaurants();
    _featuredDishesFuture = _loadFeaturedDishes();
    _heroTimer = Timer.periodic(const Duration(seconds: 7), (_) {
      if (!mounted || !_heroController.hasClients) return;
      final next = (_heroIndex + 1) % 3;
      _heroController.animateToPage(next, duration: const Duration(milliseconds: 650), curve: Curves.easeOutCubic);
    });
  }

  Future<List<MenuItem>> _loadFeaturedDishes() async {
    final restaurants = await _restaurantService.getRestaurants(limit: 12, sortBy: 'rating');
    final batches = await Future.wait(
      restaurants.take(8).map((restaurant) => _restaurantService.getMenuItems(restaurant.id)),
    );
    final dishes = batches.expand((items) => items).where((item) => item.isAvailable && (_selectedCategory == 'Todos' || item.category?.toLowerCase().contains(_selectedCategory.toLowerCase()) == true)).toList()
      ..sort((a, b) => b.rating.compareTo(a.rating));
    return dishes.take(12).toList();
  }

  Future<List<Restaurant>> _loadRestaurants() {
    final query = _searchController.text.trim();
    return _restaurantService.getRestaurants(
      searchQuery: query.isEmpty ? null : query,
      category: _selectedCategory == 'Todos' ? null : _selectedCategory,
      sortBy: 'rating',
      limit: 200,
    );
  }

  void _search() => setState(() => _restaurantsFuture = _loadRestaurants());

  void _selectCategory(String category) {
    setState(() {
      _selectedCategory = category;
      _restaurantsFuture = _loadRestaurants();
      _featuredDishesFuture = _loadFeaturedDishes();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _heroTimer?.cancel();
    _heroController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020817),
      appBar: AppBar(
        backgroundColor: const Color(0xFF020817),
        foregroundColor: Colors.white,
        title: RichText(text: const TextSpan(children: [TextSpan(text: 'Deli', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 26, letterSpacing: 1.2)), TextSpan(text: 'G', style: TextStyle(color: Color(0xFFFFB000), fontWeight: FontWeight.w900, fontSize: 28, letterSpacing: 1.2)), TextSpan(text: 'O', style: TextStyle(color: Color(0xFFFF4D0A), fontWeight: FontWeight.w900, fontSize: 28, letterSpacing: 1.2))])),
        actions: [
          IconButton(
            tooltip: 'Baixar aplicação Android',
            onPressed: () => launchUrl(
              Uri.parse('https://drive.google.com/file/d/1xsE3kekCDu3tRPFI2tUuzgg-SzOU5nvp/view?usp=sharing'),
              mode: LaunchMode.externalApplication,
            ),
            icon: const Icon(Icons.android_rounded, color: Color(0xFF8ED081)),
          ),
          IconButton(
            tooltip: 'Carrinho',
            onPressed: () => context.push('/cart'),
            icon: const Icon(Icons.shopping_bag_outlined),
          ),
          TextButton(onPressed: () => context.go('/login'), child: const Text('Entrar / Registar', style: TextStyle(color: Colors.white))),
          const SizedBox(width: 8),
        ],
      ),
      body: LayoutBuilder(builder: (context, constraints) {
        final content = RefreshIndicator(
          onRefresh: () async => setState(() {
            _restaurantsFuture = _loadRestaurants();
            _featuredDishesFuture = _loadFeaturedDishes();
          }),
          child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
          children: [
            const _AnnouncementTicker(),
            const SizedBox(height: 12),
            _GuestHero(controller: _heroController, onPageChanged: (index) => setState(() => _heroIndex = index)),
            const SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(3, (index) => AnimatedContainer(duration: const Duration(milliseconds: 250), margin: const EdgeInsets.symmetric(horizontal: 4), width: index == _heroIndex ? 26 : 8, height: 7, decoration: BoxDecoration(color: index == _heroIndex ? const Color(0xFFFF4D0A) : const Color(0xFF45668F), borderRadius: BorderRadius.circular(10))))),
            const SizedBox(height: 24),
            Text('Encontra o teu próximo sabor', style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text('Escolhe uma categoria ou procura o que te apetece hoje.', style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: const Color(0xFF9FB3D1))),
            const SizedBox(height: 18),
            TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              cursorColor: const Color(0xFFFF4D0A),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                hintText: 'Pesquisar restaurantes',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(onPressed: _search, icon: const Icon(Icons.arrow_forward_rounded)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: Color(0xFF2D5A91))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: Color(0xFF2D5A91))),
                filled: true,
                fillColor: const Color(0xFF07152D),
                hintStyle: const TextStyle(color: Color(0xFF8BA4C6)),
                suffixIconColor: const Color(0xFFFF4D0A),
              ),
            ),
            const SizedBox(height: 20),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: _categories.map((category) => Padding(
                padding: const EdgeInsets.only(right: 10),
                child: ChoiceChip(
                avatar: Icon(_categoryIcon(category), size: 17, color: _selectedCategory == category ? Colors.white : const Color(0xFFFF7A45)),
                label: Text(category, style: const TextStyle(fontSize: 13)),
                selected: _selectedCategory == category,
                onSelected: (_) => _selectCategory(category),
                selectedColor: const Color(0xFFFF4D0A),
                backgroundColor: const Color(0xFF07152D),
                side: const BorderSide(color: Color(0xFF234875)),
                labelStyle: TextStyle(fontWeight: FontWeight.w700, color: _selectedCategory == category ? Colors.white : const Color(0xFFB9D7FF)),
              ))).toList()),
            ),
            const SizedBox(height: 28),
            if (_selectedCategory == 'Todos') Row(children: [
              Expanded(child: Text('Pratos em destaque', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w900))),
              const Icon(Icons.local_fire_department_rounded, color: Color(0xFFFF7A45)),
            ]),
            if (_selectedCategory == 'Todos') const SizedBox(height: 12),
            if (_selectedCategory == 'Todos') FutureBuilder<List<MenuItem>>(
              future: _featuredDishesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const SizedBox(height: 180, child: Center(child: CircularProgressIndicator()));
                if (snapshot.hasError) return const _MessageCard(icon: Icons.restaurant_menu_outlined, message: 'Os pratos em destaque estarão disponíveis em breve.');
                final dishes = snapshot.data ?? const <MenuItem>[];
                if (dishes.isEmpty) return const _MessageCard(icon: Icons.restaurant_menu_outlined, message: 'Ainda não há pratos publicados.');
                return SizedBox(height: 230, child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: dishes.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 14),
                  itemBuilder: (_, index) => _DishCard(item: dishes[index]),
                ));
              },
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(child: Text(_selectedCategory == 'Todos' ? 'Restaurantes em destaque' : _selectedCategory, style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w900))),
                TextButton(onPressed: () => setState(() => _restaurantsFuture = _loadRestaurants()), child: Text(_selectedCategory == 'Todos' ? 'Ver todos' : 'Ver todos em $_selectedCategory', style: const TextStyle(color: Color(0xFFFF7A45)))),
              ],
            ),
            FutureBuilder<List<Restaurant>>(
              future: _restaurantsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()));
                }
                if (snapshot.hasError) {
                  return _MessageCard(icon: Icons.cloud_off_outlined, message: 'Não foi possível carregar os restaurantes.', actionLabel: 'Tentar novamente', onAction: _search);
                }
                final restaurants = snapshot.data ?? const <Restaurant>[];
                if (restaurants.isEmpty) {
                  return const _MessageCard(icon: Icons.restaurant_outlined, message: 'Ainda não há restaurantes disponíveis.');
                }
                return Column(children: restaurants.map((restaurant) => _RestaurantCard(restaurant: restaurant)).toList());
              },
            ),
            if (_selectedCategory == 'Todos') ...[
              const SizedBox(height: 24),
              const _GuestExperiencePanels(),
            ],
            const SizedBox(height: 28),
            const _MinimalFooter(),
          ],
        ));
        if (constraints.maxWidth < 1000) return content;
        return Row(children: [const _GuestSidebar(), Expanded(child: content)]);
      }),
    );
  }

  IconData _categoryIcon(String category) {
    final match = DeligoFoodCategories.list.cast<DeligoFoodCategory?>().firstWhere(
      (item) => item?.label.toLowerCase() == category.toLowerCase(),
      orElse: () => null,
    );
    return match?.icon ?? (category == 'Todos' ? Icons.grid_view_rounded : Icons.restaurant_rounded);
  }
}

class _GuestHero extends StatelessWidget {
  const _GuestHero({required this.controller, required this.onPageChanged});
  final PageController controller;
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context) {
    final slides = [
      (title: 'A tua próxima refeição começa aqui.', text: 'Descobre restaurantes, escolhe os teus pratos favoritos e acompanha a tua entrega.', image: 'assets/marketing/deligo-food-hero.png', primary: 'Explorar restaurantes', secondary: 'Entrar', action: () => context.go('/home')),
      (title: 'O teu restaurante merece chegar mais longe.', text: 'Apresenta os teus pratos, recebe pedidos e alcança novos clientes com a DeliGo.', image: 'assets/marketing/maputo-deligo-hero.png', primary: 'Quero ser parceiro', secondary: 'Conhecer vantagens', action: () => context.go('/register?role=restaurant')),
      (title: 'Mais perto. Mais simples. Mais DeliGo.', text: 'Uma experiência de entrega pensada para aproximar pessoas e restaurantes.', image: 'assets/marketing/deligo-food-hero.png', primary: 'Começar agora', secondary: 'Continuar a explorar', action: () => context.go('/register')),
    ];
    return SizedBox(height: 245, child: Stack(children: [
      PageView.builder(
        controller: controller,
        onPageChanged: onPageChanged,
        itemCount: slides.length,
        itemBuilder: (context, index) {
        final slide = slides[index];
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(28), image: DecorationImage(image: AssetImage(slide.image), fit: BoxFit.cover, colorFilter: const ColorFilter.mode(Color(0x99020817), BlendMode.darken)), boxShadow: const [BoxShadow(color: Color(0x44000000), blurRadius: 20, offset: Offset(0, 8))]),
          child: Padding(padding: const EdgeInsets.all(28), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.end, children: [
            SizedBox(width: 570, child: Text(slide.title, style: const TextStyle(color: Colors.white, fontSize: 30, height: 1.05, fontWeight: FontWeight.w900))),
            const SizedBox(height: 9),
            SizedBox(width: 540, child: Text(slide.text, style: const TextStyle(color: Color(0xFFD1E4FF), fontSize: 15))),
            const SizedBox(height: 17),
            Row(children: [FilledButton(onPressed: slide.action, style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFF4D0A), foregroundColor: Colors.white), child: Text(slide.primary)), const SizedBox(width: 12), OutlinedButton(onPressed: () => context.go('/login'), style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54)), child: Text(slide.secondary))]),
          ])),
        );
        },
      ),
    ]));
  }
}
class _GuestExperiencePanels extends StatelessWidget {
  const _GuestExperiencePanels();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 720;
        final panels = [
          Expanded(child: _InfoPanel(
            icon: Icons.delivery_dining_rounded,
            title: 'Acompanhe o seu pedido',
            subtitle: 'Do restaurante até à sua porta.',
            accent: const Color(0xFFFF4D0A),
            children: const [
              _InfoStep(label: 'Pedido confirmado', icon: Icons.check_circle, done: true),
              _InfoStep(label: 'A preparar', icon: Icons.restaurant, done: true),
              _InfoStep(label: 'A caminho', icon: Icons.two_wheeler, done: false),
            ],
          )),
          const SizedBox(width: 14, height: 14),
          Expanded(child: _InfoPanel(
            icon: Icons.verified_user_outlined,
            title: 'Comer bem, com confiança',
            subtitle: 'Tudo o que precisa para pedir melhor.',
            accent: const Color(0xFF28B6FF),
            children: const [
              _InfoStep(label: 'Pagamento seguro', icon: Icons.lock_outline, done: true),
              _InfoStep(label: 'Rastreamento em tempo real', icon: Icons.location_on_outlined, done: true),
              _InfoStep(label: 'Suporte 24/7', icon: Icons.headset_mic_outlined, done: true),
            ],
          )),
        ];
        return narrow ? Column(children: panels) : Row(children: panels);
      },
    );
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({required this.icon, required this.title, required this.subtitle, required this.accent, required this.children});
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [const Color(0xFF081A35), accent.withValues(alpha: .20)]),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: .55)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(icon, color: accent), const SizedBox(width: 10), Expanded(child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900)))]),
        const SizedBox(height: 5),
        Text(subtitle, style: const TextStyle(color: Color(0xFFB9D7FF))),
        const SizedBox(height: 16),
        ...children,
      ]),
    );
  }
}

class _InfoStep extends StatelessWidget {
  const _InfoStep({required this.label, required this.icon, required this.done});
  final String label;
  final IconData icon;
  final bool done;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(children: [Icon(icon, size: 19, color: done ? const Color(0xFF4ADE80) : const Color(0xFFFF7A45)), const SizedBox(width: 10), Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))]),
  );
}

class _MinimalFooter extends StatelessWidget {
  const _MinimalFooter();

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
    decoration: BoxDecoration(color: const Color(0xFF030B1A), borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFF192E50))),
    child: Column(children: [
      const _AnnouncementTicker(reverse: true),
      const SizedBox(height: 16),
      const Text('© 2026 DeliGo Triunfal, Lda. — Todos os direitos reservados.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
    ]),
  );
}

class _AnnouncementTicker extends StatefulWidget {
  const _AnnouncementTicker({this.reverse = false});
  final bool reverse;

  @override
  State<_AnnouncementTicker> createState() => _AnnouncementTickerState();
}

class _AnnouncementTickerState extends State<_AnnouncementTicker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 30),
  )..repeat();

  static const _items = [
    'DELIGO EATS · A tua comida, mais perto de ti.',
    'Descobre restaurantes e pratos disponíveis na tua zona.',
    'Explora menus, adiciona ao carrinho e pede com confiança.',
    'Suporte DeliGo disponível através dos canais oficiais.',
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: Container(
      height: 34,
      color: const Color(0xCC030B1A),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => FractionalTranslation(
          translation: Offset(
            (widget.reverse ? 1 : -1) * _controller.value * 0.12,
            0,
          ),
          child: child,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.max,
          children: [..._items, ..._items].map((item) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(children: [
              const Icon(Icons.circle, size: 6, color: Color(0xFFFF4D0A)),
              const SizedBox(width: 8),
              Text(item, style: const TextStyle(color: Color(0xFFD1E4FF), fontSize: 12, fontWeight: FontWeight.w700)),
            ]),
          )).toList(),
        ),
      ),
    ),
  );
}

class _GuestBenefitsFooter extends StatefulWidget {
  const _GuestBenefitsFooter();

  @override
  State<_GuestBenefitsFooter> createState() => _GuestBenefitsFooterState();
}

class _GuestBenefitsFooterState extends State<_GuestBenefitsFooter> {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(26, 26, 26, 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF101E38), Color(0xFF07152D)]),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF234875)),
        boxShadow: const [BoxShadow(color: Color(0x44000000), blurRadius: 18, offset: Offset(0, 8))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        LayoutBuilder(builder: (context, constraints) {
          final compact = constraints.maxWidth < 650;
          final heading = Row(children: [
            Container(width: 46, height: 46, decoration: BoxDecoration(color: const Color(0xFFFF4D0A), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.restaurant_rounded, color: Colors.white)),
            const SizedBox(width: 14),
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Comida mais perto de ti.', style: TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w900)),
              SizedBox(height: 4),
              Text('Uma experiência DeliGo simples, segura e feita para Maputo.', style: TextStyle(color: Color(0xFFB9D7FF))),
            ])),
          ]);
          final partner = OutlinedButton.icon(onPressed: () => context.go('/register?role=restaurant'), icon: const Icon(Icons.arrow_forward_rounded), label: const Text('Quero ser parceiro'));
          return compact ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [heading, const SizedBox(height: 16), partner]) : Row(children: [Expanded(child: heading), partner]);
        }),
        const SizedBox(height: 24),
        const Divider(color: Color(0xFF234875)),
        const SizedBox(height: 18),
        LayoutBuilder(builder: (context, constraints) {
          final columns = [
            _FooterColumn(title: 'Para clientes', items: ['Descobrir restaurantes', 'Como funciona', 'Suporte 24/7']),
            _FooterColumn(title: 'Para restaurantes', items: ['Ser parceiro', 'Como aderir', 'Contacto comercial']),
            _FooterColumn(title: 'DeliGo', items: ['Pagamento seguro', 'Rastreamento em tempo real', 'Privacidade']),
          ];
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: columns.map((item) => SizedBox(width: 210, child: Padding(padding: const EdgeInsets.only(right: 24), child: item))).toList()),
          );
        }),
        const SizedBox(height: 8),
        Wrap(spacing: 10, runSpacing: 10, children: [
          OutlinedButton.icon(onPressed: () => context.go('/register?role=client'), icon: const Icon(Icons.person_add_alt_1, size: 17), label: const Text('Criar conta cliente')),
          OutlinedButton.icon(onPressed: () => context.go('/register?role=restaurant'), icon: const Icon(Icons.storefront_outlined, size: 17), label: const Text('Ser parceiro')),
          OutlinedButton.icon(onPressed: () => launchUrl(Uri(scheme: 'tel', path: '841130015')), icon: const Icon(Icons.call_outlined, size: 17), label: const Text('Suporte 24/7 · 841130015')),
          OutlinedButton.icon(onPressed: () => launchUrl(Uri.parse('https://www.facebook.com/profile.php?id=61588898956501'), mode: LaunchMode.externalApplication), icon: const Icon(Icons.facebook, size: 17), label: const Text('Mensagem no Facebook')),
          OutlinedButton.icon(onPressed: () => context.go('/help'), icon: const Icon(Icons.question_answer_outlined, size: 17), label: const Text('Perguntas e respostas')),
        ]),
        const SizedBox(height: 16),
        Text('© ${DateTime.now().year} DeliGo Triunfal, Lda. — Todos os direitos reservados.', style: const TextStyle(color: Color(0xFF7892B5), fontSize: 12)),
      ]),
    );
  }
}

class _FooterColumn extends StatelessWidget {
  const _FooterColumn({required this.title, required this.items});
  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
    const SizedBox(height: 9),
    ...items.map((item) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(item, style: const TextStyle(color: Color(0xFF9FB3D1), fontSize: 13)))),
  ]);
}

class _GuestSidebar extends StatelessWidget {
  const _GuestSidebar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      color: const Color(0xFF030B1A),
      padding: const EdgeInsets.fromLTRB(18, 24, 14, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
          padding: EdgeInsets.only(left: 12, bottom: 28),
          child: Text('DeliGO', style: TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
        ),
        _GuestNavItem(icon: Icons.home_rounded, label: 'Início', selected: true, onTap: () => context.go('/home')),
        _GuestNavItem(icon: Icons.help_outline_rounded, label: 'Ajuda e suporte', onTap: () => launchUrl(Uri.parse('https://www.facebook.com/profile.php?id=61588898956501'), mode: LaunchMode.externalApplication)),
        const SizedBox(height: 14),
        const _SidebarInfoCard(
          icon: Icons.lock_outline_rounded,
          title: 'Pagamentos seguros',
          body: 'M-Pesa  ·  e-Mola  ·  Cartões\nPlataforma integrada e segura.',
        ),
        const SizedBox(height: 10),
        _SidebarInfoCard(
          icon: Icons.mail_outline_rounded,
          title: 'Contactos DeliGo',
          body: 'Apoio, institucional e carreiras',
          onTap: () => launchUrl(Uri.parse('mailto:suporte@deligoeats.com'), mode: LaunchMode.externalApplication),
        ),
        const SizedBox(height: 10),
        _SidebarInfoCard(
          icon: Icons.android_rounded,
          title: 'Aplicação Android',
          body: 'Baixar a app DeliGo para Android',
          onTap: () => launchUrl(
            Uri.parse('https://drive.google.com/file/d/1xsE3kekCDu3tRPFI2tUuzgg-SzOU5nvp/view?usp=sharing'),
            mode: LaunchMode.externalApplication,
          ),
        ),
        const Spacer(),
        const _GuestTicker(),
      ]),
    );
  }
}

class _SidebarInfoCard extends StatelessWidget {
  const _SidebarInfoCard({required this.icon, required this.title, required this.body, this.onTap});
  final IconData icon;
  final String title;
  final String body;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(11, 11, 10, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF08162B),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0x334B76A8)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 19, color: const Color(0xFFFF7A45)),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(body, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF9FB3D1), fontSize: 10, height: 1.3)),
        ])),
      ]),
    );
    return onTap == null ? card : InkWell(onTap: onTap, borderRadius: BorderRadius.circular(13), child: card);
  }
}

class _GuestNavItem extends StatelessWidget {
  const _GuestNavItem({required this.icon, required this.label, required this.onTap, this.selected = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: ListTile(
      dense: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      tileColor: selected ? const Color(0xFFFF4D0A) : Colors.transparent,
      leading: Icon(icon, color: selected ? Colors.white : const Color(0xFF9FB3D1)),
      title: Text(label, style: TextStyle(color: selected ? Colors.white : const Color(0xFFB9D7FF), fontWeight: FontWeight.w700, fontFamily: 'Trebuchet MS', shadows: selected ? const [Shadow(color: Color(0xFFFF4D0A), blurRadius: 10)] : const [Shadow(color: Color(0xFFFF7A45), blurRadius: 4)])),
      onTap: onTap,
    ),
  );
}

class _GuestTicker extends StatefulWidget {
  const _GuestTicker();

  @override
  State<_GuestTicker> createState() => _GuestTickerState();
}

class _GuestTickerState extends State<_GuestTicker> {
  static const _fallbackPhrases = <String>[
    'Descobre sabores incríveis em Maputo, a DeliGo entrega à porta da sua casa!',
  ];
  List<String> _phrases = _fallbackPhrases;
  var _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _loadPhrases();
    _timer = Timer.periodic(const Duration(milliseconds: 4500), (_) {
      if (mounted && _phrases.isNotEmpty) {
        setState(() => _index = (_index + 1) % _phrases.length);
      }
    });
  }

  Future<void> _loadPhrases() async {
    try {
      final raw = await rootBundle.loadString('assets/guest/deligo_live_365.txt');
      final phrases = raw
          .split(RegExp(r'\r?\n'))
          .map((line) => line.replaceFirst(RegExp(r'^\s*\d+\.\s*'), '').trim())
          .where((line) => line.isNotEmpty)
          .toList(growable: false);
      if (mounted && phrases.isNotEmpty) {
        final randomized = List<String>.from(phrases)..shuffle(Random());
        setState(() => _phrases = randomized);
      }
    } catch (_) {
      // Keep the first phrase visible if the optional ticker asset is absent.
    }
  }

  @override
  void dispose() { _timer?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Container(
    height: 184,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      gradient: const LinearGradient(colors: [Color(0xFF101E38), Color(0xFF24121B)], begin: Alignment.topLeft, end: Alignment.bottomRight),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0x66FF4D0A)),
      boxShadow: const [BoxShadow(color: Color(0x331F0A00), blurRadius: 18)],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 9, height: 9, decoration: const BoxDecoration(color: Color(0xFFFF4D0A), shape: BoxShape.circle, boxShadow: [BoxShadow(color: Color(0xFFFF4D0A), blurRadius: 8)])),
        const SizedBox(width: 7),
        const Text('DELIGO LIVE', style: TextStyle(color: Color(0xFFFF7A45), fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
      ]),
      const SizedBox(height: 14),
      Expanded(child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 650),
        transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: SlideTransition(position: Tween(begin: const Offset(0, .18), end: Offset.zero).animate(animation), child: child)),
        child: Text('“${_phrases[_index]}”', key: ValueKey(_index), style: const TextStyle(color: Colors.white, height: 1.35, fontWeight: FontWeight.w700)),
      )),
    ]),
  );
}

class _DishCard extends StatelessWidget {
  const _DishCard({required this.item});
  final MenuItem item;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 205,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => context.push('/restaurant/${item.restaurantId}'),
        child: Container(
          decoration: BoxDecoration(color: const Color(0xFF07152D), borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFF193B68))),
          clipBehavior: Clip.antiAlias,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(height: 112, width: double.infinity, child: item.imageUrl?.trim().isNotEmpty == true
              ? Image.network(item.imageUrl!, fit: BoxFit.cover)
              : const ColoredBox(color: Color(0xFF10294A), child: Icon(Icons.restaurant_menu_rounded, color: Color(0xFFFF7A45), size: 38))),
            Padding(padding: const EdgeInsets.fromLTRB(12, 10, 12, 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
              const SizedBox(height: 5),
              Text('${item.price.toStringAsFixed(2)} MZN  ·  ${item.prepTimeMinutes} min', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFB9D7FF), fontSize: 12)),
              const SizedBox(height: 4),
              Text('★ ${item.rating.toStringAsFixed(1)}', style: const TextStyle(color: Color(0xFFFFB020), fontWeight: FontWeight.w700, fontSize: 12)),
            ])),
          ]),
        ),
      ),
    );
  }
}

class _RestaurantCard extends StatelessWidget {
  const _RestaurantCard({required this.restaurant});
  final Restaurant restaurant;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF07152D),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF193B68)),
        boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 12, offset: Offset(0, 5))],
      ),
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: SizedBox(
          width: 64,
          height: 64,
          child: restaurant.imageUrl?.trim().isNotEmpty == true
              ? Image.network(restaurant.imageUrl!, fit: BoxFit.cover)
              : const DecoratedBox(decoration: BoxDecoration(color: Color(0xFFFEE2E2)), child: Icon(Icons.restaurant, color: Colors.red)),
        ),
        title: Text(restaurant.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        subtitle: Text([
          if (restaurant.neighborhood?.trim().isNotEmpty == true) restaurant.neighborhood!,
          if (restaurant.rating != null) '★ ${restaurant.rating!.toStringAsFixed(1)}',
        ].join('  ·  '), style: const TextStyle(color: Color(0xFF9FB3D1))),
        trailing: const Icon(Icons.chevron_right_rounded, color: Color(0xFFFF4D0A)),
        onTap: () => context.push('/restaurant/${restaurant.id}'),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.icon, required this.message, this.actionLabel, this.onAction});
  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Card(color: const Color(0xFF07152D), child: Padding(padding: const EdgeInsets.all(28), child: Column(children: [
      Icon(icon, size: 40),
      const SizedBox(height: 12),
      Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFB9D7FF))),
      if (actionLabel != null) ...[const SizedBox(height: 12), OutlinedButton(onPressed: onAction, child: Text(actionLabel!))],
    ])));
  }
}
