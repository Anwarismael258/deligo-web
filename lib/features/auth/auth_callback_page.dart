import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/router/app_router.dart';
import '../../config/theme/app_colors.dart';

class AuthCallbackPage extends StatefulWidget {
  const AuthCallbackPage({super.key});

  @override
  State<AuthCallbackPage> createState() => _AuthCallbackPageState();
}

class _AuthCallbackPageState extends State<AuthCallbackPage> {
  String _title = 'Verificacao concluida';
  String _message =
      'A autenticacao foi validada com sucesso. Entre novamente no app para continuar.';
  bool _isRecovery = false;
  bool _hasNavigated = false;
  String? _verifiedEmail;

  @override
  void initState() {
    super.initState();
    _handleCallback();
  }

  Future<void> _handleCallback() async {
    await Future.delayed(const Duration(milliseconds: 600));

    final uri = Uri.base;
    final queryType = uri.queryParameters['type'];
    final fragment = uri.fragment;
    final fragmentPayload =
        fragment.startsWith('#') ? fragment.substring(1) : fragment;
    final fragmentParams = fragmentPayload.isEmpty
        ? <String, String>{}
        : Uri.splitQueryString(fragmentPayload);
    final type = queryType ?? fragmentParams['type'];

    if (!mounted) return;

    setState(() {
      if (type == 'recovery') {
        _isRecovery = true;
        _title = 'Link validado com sucesso';
        _message =
            'Recebemos o seu link de recuperacao. Agora voce ja pode definir a sua nova senha com seguranca.';
      } else {
        _isRecovery = false;
        _verifiedEmail =
            Supabase.instance.client.auth.currentUser?.email ??
            uri.queryParameters['email'] ??
            fragmentParams['email'];
        _title = 'Email confirmado com sucesso';
        _message =
            'Cadastro realizado com sucesso. O seu email ja foi verificado e agora pode entrar no app com a sua conta.';
      }
    });

    if (!_isRecovery) {
      unawaited(_autoGoToLogin());
    }
  }

  Future<void> _autoGoToLogin() async {
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted || _hasNavigated) return;
    await _goToLogin();
  }

  Future<void> _goToLogin() async {
    if (_hasNavigated) return;
    _hasNavigated = true;

    if (_isRecovery) {
      if (!mounted) return;
      context.go('/reset-password');
      return;
    }

    try {
      AuthRefreshNotifier.markIntentionalSignOut();
      await Supabase.instance.client.auth.signOut();
    } catch (_) {
      // Se nao existir sessao, seguimos normalmente.
    }

    if (!mounted) return;

    final emailQuery = (_verifiedEmail != null && _verifiedEmail!.isNotEmpty)
        ? '&email=${Uri.encodeComponent(_verifiedEmail!)}'
        : '';
    context.go('/login?status=email_verified$emailQuery');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.mark_email_read,
                color: AppColors.successGreen,
                size: 72,
              ),
              const SizedBox(height: 16),
              Text(
                _title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.neutralGray),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _goToLogin,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryRed,
                    foregroundColor: AppColors.cleanWhite,
                  ),
                  child: Text(_isRecovery ? 'Definir nova senha' : 'Ir para Login'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
