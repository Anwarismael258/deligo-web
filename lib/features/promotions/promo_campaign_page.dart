import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/theme/app_colors.dart';
import '../../services/firebase_analytics_service.dart';

class PromoCampaignPage extends StatefulWidget {
  final String campaignId;
  final String? restaurantId;
  final String? title;
  final String? body;
  final String? source;

  const PromoCampaignPage({
    super.key,
    required this.campaignId,
    this.restaurantId,
    this.title,
    this.body,
    this.source,
  });

  @override
  State<PromoCampaignPage> createState() => _PromoCampaignPageState();
}

class _PromoCampaignPageState extends State<PromoCampaignPage> {
  @override
  void initState() {
    super.initState();
    FirebaseAnalyticsService.instance.logPromoOpen(
      campaignId: widget.campaignId,
      restaurantId: widget.restaurantId,
      source: widget.source,
    );
  }

  void _openPromoTarget() {
    final user = Supabase.instance.client.auth.currentUser;
    final restaurantId = widget.restaurantId?.trim() ?? '';
    if (restaurantId.isNotEmpty) {
      if (user == null) {
        context.go('/login');
        return;
      }
      context.go('/restaurant/$restaurantId');
      return;
    }

    if (user == null) {
      context.go('/login');
      return;
    }
    context.go('/client-dashboard?tab=explore');
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.title?.trim().isNotEmpty == true
        ? widget.title!.trim()
        : 'Oferta Relâmpago!';
    final body = widget.body?.trim().isNotEmpty == true
        ? widget.body!.trim()
        : 'Promoção ativa no DeliGo. Toque abaixo para abrir a melhor rota.';

    return Scaffold(
      backgroundColor: const Color(0xFFFFF7F2),
      appBar: AppBar(
        title: const Text('Campanha DeliGo'),
        backgroundColor: AppColors.primaryRed,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFE2D2), Color(0xFFFFF1E9)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '🔥 Campanha ativa',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primaryRed,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      body,
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.45,
                        color: AppColors.darkGray,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Campanha: ${widget.campaignId}',
                style: const TextStyle(
                  color: AppColors.neutralGray,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (widget.restaurantId?.isNotEmpty == true) ...[
                const SizedBox(height: 8),
                Text(
                  'Destino direto: restaurante ${widget.restaurantId}',
                  style: const TextStyle(
                    color: AppColors.neutralGray,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _openPromoTarget,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryRed,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  icon: const Icon(Icons.local_offer_outlined),
                  label: const Text('Abrir promoção'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
