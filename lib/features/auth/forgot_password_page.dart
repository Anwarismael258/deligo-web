import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/theme/app_colors.dart';
import '../../config/router/app_router.dart';
import '../../services/phone_auth_service.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _phoneController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  String _normalizeMozPhone(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('258') && digits.length >= 12) {
      return '+$digits';
    }
    if (digits.length == 9) {
      return '+258$digits';
    }
    return value.trim();
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

  String _friendlyOtpRequestMessage(String rawMessage) {
    final normalized = rawMessage.toLowerCase();
    if (normalized.contains('user not found') ||
        normalized.contains('nao existe conta') ||
        normalized.contains('conta')) {
      return 'Ainda nao encontramos uma conta com este numero.';
    }
    if (normalized.contains('too many') || normalized.contains('rate')) {
      return 'Muitas tentativas seguidas. Aguarde um pouco e tente novamente.';
    }
    if (normalized.contains('invalid phone')) {
      return 'Numero de telefone invalido. Use +258XXXXXXXXX.';
    }
    if ((normalized.contains('sms') && normalized.contains('disabled')) ||
        normalized.contains('phone provider') ||
        normalized.contains('mozesms')) {
      return 'O envio de SMS nao esta configurado corretamente. Verifique a integracao da MozeSMS.';
    }
    return 'Nao foi possivel enviar o codigo SMS agora.';
  }

  Future<void> _sendResetOtp() async {
    final phone = _normalizeMozPhone(_phoneController.text.trim());
    final phoneRegex = RegExp(r'^(\+258|258)?[8-9]\d{8}$');

    if (phone.isEmpty || !phoneRegex.hasMatch(phone)) {
      _showAppSnack('Numero de telefone invalido. Use +258XXXXXXXXX.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      // A stale authenticated session must not be allowed to hijack the public
      // recovery route and redirect the customer back to a dashboard.
      AuthRefreshNotifier.markIntentionalSignOut();
      await Supabase.instance.client.auth.signOut();
      await PhoneAuthService.instance.requestOtp(phone: phone, flow: 'reset');
      if (!mounted) return;
      context.go(
        '/phone-otp?flow=reset&phone=${Uri.encodeQueryComponent(phone)}',
      );
    } on AuthException catch (e) {
      _showAppSnack(_friendlyOtpRequestMessage(e.message));
    } catch (e) {
      _showAppSnack(_friendlyOtpRequestMessage(e.toString()));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recuperar senha'),
        centerTitle: true,
        backgroundColor: AppColors.primaryRed,
        foregroundColor: AppColors.cleanWhite,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            elevation: 6,
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                children: [
                  const Icon(
                    Icons.sms_outlined,
                    size: 64,
                    color: AppColors.primaryRed,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Recuperar senha',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryRed,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Enviaremos um OTP para confirmar o numero.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: AppColors.darkGray),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _phoneController,
                    enabled: !_isLoading,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: 'Numero de telefone',
                      hintText: '84XXXXXXX',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      prefixIcon: const Icon(Icons.phone_android),
                      prefixText: '+258 ',
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _sendResetOtp,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryRed,
                        foregroundColor: Colors.white,
                      ),
                      icon: _isLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : const Icon(Icons.sms),
                      label: Text(_isLoading ? 'A enviar...' : 'Enviar OTP'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _isLoading ? null : () => context.go('/login'),
                    child: const Text('Voltar ao login'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
