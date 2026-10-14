import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/theme/app_colors.dart';
import '../../services/restaurant_share_service.dart';
import '../../shared/models/restaurant.dart';

class RestaurantInvitePage extends StatefulWidget {
  final String shareToken;

  const RestaurantInvitePage({super.key, required this.shareToken});

  @override
  State<RestaurantInvitePage> createState() => _RestaurantInvitePageState();
}

class _RestaurantInvitePageState extends State<RestaurantInvitePage> {
  final RestaurantShareService _shareService = RestaurantShareService();
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _loading = true;
  Restaurant? _restaurant;
  String _referralCode = '';
  String _landingTitle = '';
  String _landingSubtitle = '';
  String _inviterName = 'um cliente DeliGo';
  String _shareId = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await _shareService.getLandingDataByToken(widget.shareToken);
    if (!mounted) return;
    if (data == null) {
      setState(() => _loading = false);
      return;
    }

    final restaurant = data['restaurant'] as Restaurant;
    final metadata = data['metadata'] as Map<String, dynamic>;
    final shareId = data['share_id']?.toString() ?? '';
    if (shareId.isNotEmpty) {
      await _shareService.recordEvent(
        shareId: shareId,
        eventType: 'landing_opened',
        metadata: {'share_token': widget.shareToken},
      );
    }

    setState(() {
      _restaurant = restaurant;
      _shareId = shareId;
      _referralCode = data['referral_code']?.toString() ?? '';
      _landingTitle = 'Voce foi convidado para comer no ${restaurant.name}';
      _landingSubtitle =
          'Convite enviado por ${metadata['inviter_name'] ?? _inviterName}. Abra o restaurante no DeliGo para consultar o menu.';
      _inviterName = metadata['inviter_name']?.toString() ?? _inviterName;
      _loading = false;
    });
  }

  Future<void> _openRestaurantFromInvite() async {
    if (_restaurant == null) return;
    await _shareService.stashPendingInviteLocally(
      shareToken: widget.shareToken,
      restaurantId: _restaurant!.id,
    );

    if (_supabase.auth.currentUser == null) {
      if (_shareId.isNotEmpty) {
        await _shareService.recordEvent(
          shareId: _shareId,
          eventType: 'invite_cta_requires_login',
          metadata: {'restaurant_id': _restaurant!.id},
        );
      }
      if (!mounted) return;
      context.go('/login');
      return;
    }

    await _shareService.bindInviteToCurrentUser(
      shareToken: widget.shareToken,
      restaurantId: _restaurant!.id,
    );
    if (_shareId.isNotEmpty) {
      await _shareService.recordEvent(
        shareId: _shareId,
        eventType: 'invite_cta_open_restaurant',
        metadata: {'restaurant_id': _restaurant!.id},
      );
    }
    if (!mounted) return;
    context.push('/restaurant/${_restaurant!.id}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F7F4),
      appBar: AppBar(
        title: const Text('Convite DeliGo'),
        backgroundColor: AppColors.primaryRed,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _restaurant == null
          ? const Center(child: Text('Convite nao encontrado'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: _restaurant!.imageUrl?.isNotEmpty == true
                      ? Image.network(
                          _restaurant!.imageUrl!,
                          height: 220,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              _placeholder(),
                        )
                      : _placeholder(),
                ),
                const SizedBox(height: 18),
                Text(
                  _landingTitle,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _landingSubtitle,
                  style: const TextStyle(
                    color: AppColors.neutralGray,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 18),
                _infoCard(
                  title: 'Cupom automatico',
                  value: _referralCode,
                  subtitle:
                      'Use este codigo e ganhe 10% OFF na primeira compra, com limite de 100 MZN.',
                ),
                const SizedBox(height: 12),
                _infoCard(
                  title: 'Localizacao',
                  value: _restaurant!.address,
                  subtitle:
                      'Entrega estimada em ${_restaurant!.deliveryTime ?? 25} min.',
                ),
                const SizedBox(height: 18),
                ElevatedButton.icon(
                  onPressed: _openRestaurantFromInvite,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryRed,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  icon: const Icon(Icons.shopping_bag_outlined),
                  label: const Text('Pedir agora'),
                ),
              ],
            ),
    );
  }

  Widget _infoCard({
    required String title,
    required String value,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.neutralGray,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(subtitle, style: const TextStyle(color: AppColors.neutralGray)),
        ],
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      height: 220,
      color: const Color(0xFFFFE1D6),
      child: const Center(
        child: Icon(
          Icons.restaurant_menu,
          size: 64,
          color: AppColors.primaryRed,
        ),
      ),
    );
  }
}
