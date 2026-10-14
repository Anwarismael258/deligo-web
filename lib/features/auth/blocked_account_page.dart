import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/theme/app_colors.dart';

class BlockedAccountPage extends StatefulWidget {
  const BlockedAccountPage({super.key});

  @override
  State<BlockedAccountPage> createState() => _BlockedAccountPageState();
}

class _BlockedAccountPageState extends State<BlockedAccountPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  Map<String, dynamic>? _profile;
  bool _isLoading = true;
  bool _isSigningOut = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      if (mounted) context.go('/login?status=blocked');
      return;
    }

    try {
      final response = await _supabase
          .from('profiles')
          .select('full_name, role, block_reason, is_blocked, administrative_status, administrative_reason')
          .eq('id', user.id)
          .maybeSingle();

      if (!mounted) return;
      setState(() {
        _profile = response == null
            ? null
            : Map<String, dynamic>.from(response);
        _isLoading = false;
      });

      if (response?['is_blocked'] != true) {
        context.go('/');
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _signOut() async {
    if (_isSigningOut) return;
    setState(() => _isSigningOut = true);
    try {
      await _supabase.auth.signOut();
      if (!mounted) return;
      context.go('/login?status=blocked');
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSigningOut = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nao conseguimos sair agora. Tente novamente.'),
          backgroundColor: AppColors.primaryRed,
        ),
      );
    }
  }

  void _openSupportChat() {
    final role = (_profile?['role']?.toString() ?? '').trim();
    if (role.isNotEmpty) {
      context.push('/support/$role');
      return;
    }
    context.push('/support');
  }

  @override
  Widget build(BuildContext context) {
    final role = (_profile?['role']?.toString() ?? 'conta').trim();
    final reason = (_profile?['administrative_reason']?.toString() ?? _profile?['block_reason']?.toString() ?? '').trim();
    final administrativeStatus = (_profile?['administrative_status']?.toString() ?? 'blocked').trim();
    final displayName = (_profile?['full_name']?.toString() ?? 'Conta DeliGo')
        .trim();

    return Scaffold(
      appBar: AppBar(
        title: Text(administrativeStatus == 'suspended' ? 'Conta suspensa' : administrativeStatus == 'disabled' ? 'Conta desativada' : 'Conta bloqueada'),
        backgroundColor: AppColors.primaryRed,
        foregroundColor: AppColors.cleanWhite,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      elevation: 8,
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: AppColors.primaryRed.withValues(
                                  alpha: 0.12,
                                ),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.block_rounded,
                                color: AppColors.primaryRed,
                                size: 56,
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              administrativeStatus == 'suspended' ? 'Conta temporariamente suspensa' : administrativeStatus == 'disabled' ? 'Conta desativada pela Central' : 'Conta temporariamente bloqueada',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primaryRed,
                                  ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '$displayName ($role) foi suspenso pelo administrador.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 15,
                                color: AppColors.neutralGray,
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: Colors.orange.withValues(alpha: 0.25),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Decisão da Central · motivo',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.orange,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    reason.isNotEmpty
                                        ? reason
                                        : 'A sua conta foi bloqueada temporariamente. Entre em contacto com o suporte para rever a situacao.',
                                    style: const TextStyle(
                                      fontSize: 15,
                                      color: AppColors.neutralGray,
                                      height: 1.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                            const Text(
                              'Se acredita que isto foi um engano, fale com o suporte DeliGo e aguarde a reativacao da conta.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                color: AppColors.neutralGray,
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _openSupportChat,
                                icon: const Icon(Icons.support_agent),
                                label: const Text('Falar com o suporte'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.primaryRed,
                                  side: const BorderSide(
                                    color: AppColors.primaryRed,
                                  ),
                                  minimumSize: const Size.fromHeight(48),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: _isSigningOut ? null : _signOut,
                                icon: _isSigningOut
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                Colors.white,
                                              ),
                                        ),
                                      )
                                    : const Icon(Icons.logout),
                                label: Text(
                                  _isSigningOut ? 'A sair...' : 'Sair da conta',
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primaryRed,
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size.fromHeight(48),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      ),
      floatingActionButton: _isLoading
          ? null
          : FloatingActionButton.extended(
              onPressed: _openSupportChat,
              backgroundColor: AppColors.primaryRed,
              foregroundColor: AppColors.cleanWhite,
              icon: const Icon(Icons.chat_bubble_outline),
              label: const Text('Suporte'),
            ),
    );
  }
}
