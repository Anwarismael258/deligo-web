import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/router/app_router.dart';
import '../../config/theme/app_colors.dart';

class CreatePasswordPage extends StatefulWidget {
  const CreatePasswordPage({super.key});

  @override
  State<CreatePasswordPage> createState() => _CreatePasswordPageState();
}

class _CreatePasswordPageState extends State<CreatePasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _saving = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _showAppSnack(String message, {bool success = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: success
            ? AppColors.successGreen
            : AppColors.primaryRed,
        content: Row(
          children: [
            Icon(
              success ? Icons.check_circle : Icons.error_outline,
              color: Colors.white,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }

  Future<void> _savePassword() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final client = Supabase.instance.client;
      await client.auth.updateUser(
        UserAttributes(password: _passwordController.text.trim()),
      );

      final user = client.auth.currentUser;
      if (user == null) {
        if (!mounted) return;
        _showAppSnack('Sessao expirada. Entre novamente.');
        context.go('/login');
        return;
      }

      final profile = await AppRouter.getProfile(user.id);
      final rawSettings = profile?['settings'];
      final settings = rawSettings is Map
          ? rawSettings.map((key, value) => MapEntry(key.toString(), value))
          : <String, dynamic>{};
      await client
          .from('profiles')
          .update({
            'settings': {...settings, 'password_setup_required': false},
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', user.id);

      // Every newly completed registration gets its own zero-balance wallet
      // before entering the app. Deposit/withdraw remain protected by the
      // backend phone-verification check, but no role should see a missing
      // wallet after signup.
      try {
        await client.functions.invoke(
          'ensure-wallet',
          body: {
            'role': profile?['role'],
            'full_name': profile?['full_name'],
            'phone': user.phone ?? user.userMetadata?['phone'],
            'email': user.email,
          },
        );
      } catch (_) {
        // The authenticated bootstrap retries this on the next app start.
      }

      final role = profile?['role']?.toString() ?? 'client';
      final kycStatus = profile?['kyc_status']?.toString();
      final destination = AppRouter.destinationForRole(
        role,
        kycStatus: kycStatus,
        emailConfirmed: true,
        phoneVerificationRequired: false,
      );

      if (!mounted) return;
      _showAppSnack('Senha criada com sucesso.', success: true);
      context.go(destination);
    } on AuthException catch (e) {
      _showAppSnack(e.message);
    } catch (_) {
      _showAppSnack(
        'Nao conseguimos criar a senha agora. Tente novamente em instantes.',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Criar senha'),
        centerTitle: true,
        backgroundColor: AppColors.primaryRed,
        foregroundColor: AppColors.cleanWhite,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 6,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.lock_outline,
                      color: AppColors.primaryRed,
                      size: 64,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Defina a sua senha',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryRed,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Esta senha sera usada nos proximos logins.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.neutralGray),
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      enabled: !_saving,
                      decoration: InputDecoration(
                        labelText: 'Nova senha',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Informe a nova senha';
                        }
                        if (value.length < 6) {
                          return 'A senha deve ter pelo menos 6 caracteres';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _confirmPasswordController,
                      obscureText: _obscureConfirmPassword,
                      enabled: !_saving,
                      decoration: InputDecoration(
                        labelText: 'Confirmar senha',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        prefixIcon: const Icon(Icons.lock),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureConfirmPassword
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                          onPressed: () => setState(
                            () => _obscureConfirmPassword =
                                !_obscureConfirmPassword,
                          ),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Confirme a senha';
                        }
                        if (value != _passwordController.text) {
                          return 'As senhas nao coincidem';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _saving ? null : _savePassword,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryRed,
                          foregroundColor: AppColors.cleanWhite,
                        ),
                        child: _saving
                            ? const SizedBox(
                                height: 24,
                                width: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : const Text('Salvar senha'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
