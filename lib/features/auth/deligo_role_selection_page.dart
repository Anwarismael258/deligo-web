import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/theme/app_colors.dart';
import '../../services/deligo_role_service.dart';
import '../../services/auth_session_bootstrap_service.dart';

class DeligoRoleSelectionPage extends StatefulWidget {
  const DeligoRoleSelectionPage({super.key});
  @override
  State<DeligoRoleSelectionPage> createState() =>
      _DeligoRoleSelectionPageState();
}

class _DeligoRoleSelectionPageState extends State<DeligoRoleSelectionPage> {
  bool _loading = false;
  Future<void> _choose(String slug) async {
    setState(() => _loading = true);
    try {
      final role = await DeligoRoleService.instance.activate(slug);
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        await AuthSessionBootstrapService.instance.prepareAuthenticatedUser(
          user,
        );
      }
      if (!mounted) {
        return;
      }
      final destination = switch (slug) {
        'deligo_restaurant' => '/restaurant-dashboard',
        'deligo_courier' => '/courier-dashboard',
        _ => '/client-dashboard',
      };
      context.go(role.status == 'active' ? destination : '/kyc-pending');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível guardar a sua escolha. Tente novamente.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('DeliGo')),
    body: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Como deseja começar no DeliGo?',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          const Text(
            'A sua Conta Triunfal foi encontrada. Escolha apenas como pretende utilizar o DeliGo.',
          ),
          const SizedBox(height: 28),
          _choice(
            'Pedir comida',
            'Cliente',
            Icons.restaurant_menu,
            'deligo_customer',
          ),
          _choice(
            'Trabalhar como estafeta',
            'A candidatura será analisada antes de operar.',
            Icons.delivery_dining,
            'deligo_courier',
          ),
          _choice(
            'Cadastrar um restaurante',
            'O estabelecimento ficará pendente de análise.',
            Icons.storefront,
            'deligo_restaurant',
          ),
        ],
      ),
    ),
  );
  Widget _choice(String title, String subtitle, IconData icon, String slug) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: OutlinedButton.icon(
          onPressed: _loading ? null : () => _choose(slug),
          icon: Icon(icon, color: AppColors.primaryRed),
          label: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(subtitle),
              ],
            ),
          ),
          style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft),
        ),
      );
}
