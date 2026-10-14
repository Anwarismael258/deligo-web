import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/router/app_router.dart';
import '../../config/theme/app_colors.dart';
import '../../services/phone_auth_service.dart';
import '../../services/trust_safety_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.status, this.initialPhone});

  final String? status;
  final String? initialPhone;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  final _phoneController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _otpController = TextEditingController();
  late final AnimationController _bikeController;

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _fieldFirstAccess = false;
  final _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _bikeController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
    final seededPhone = widget.initialPhone?.trim();
    if (seededPhone != null && seededPhone.isNotEmpty) {
      _phoneController.text = seededPhone.replaceFirst(RegExp(r'^\+?258'), '');
    } else {
      _phoneController.text = '';
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      switch (widget.status) {
        case 'password_reset':
          _showAppSnack(
            'Link validado. Agora entre novamente para continuar.',
            success: true,
          );
          break;
        case 'session_expired':
          _showAppSnack(
            'A sua sessao expirou. Entre novamente para continuar.',
          );
          break;
        case 'blocked':
          _showAppSnack(
            'A sua conta esta bloqueada temporariamente. Fale com o suporte para rever a situacao.',
          );
          break;
        case 'unblocked':
          _showAppSnack(
            'A sua conta foi desbloqueada. Ja pode voltar a entrar no app.',
            success: true,
          );
          break;
      }
    });
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _fullNameController.dispose();
    _otpController.dispose();
    _passwordController.dispose();
    _bikeController.dispose();
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

  String _friendlyLoginMessage(String rawMessage) {
    final msg = rawMessage.toLowerCase();
    if (msg.contains('codigo')) {
      if (msg.contains('expirou') || msg.contains('nao foi encontrado')) {
        return 'O codigo expirou ou nao foi encontrado. Reenvie o convite pelo Admin.';
      }
      if (msg.contains('limite')) {
        return 'Limite de tentativas excedido. Reenvie o convite pelo Admin.';
      }
      return 'Codigo OTP invalido. Confirme os 6 digitos recebidos por SMS.';
    }
    if (msg.contains('convite')) {
      if (msg.contains('nome') || msg.contains('corresponde')) {
        return 'O nome informado precisa ser exatamente o nome usado no convite.';
      }
      return rawMessage;
    }
    if (msg.contains('sessao')) {
      return 'Nao foi possivel abrir a sessao agora. Reenvie o convite e tente novamente.';
    }
    if (msg.contains('user not found') ||
        msg.contains('nao existe conta com este numero') ||
        msg.contains('conta com este numero') ||
        msg.contains('signup') ||
        msg.contains('create')) {
      return 'Ainda nao encontramos uma conta com este numero.';
    }
    if (msg.contains('too many') || msg.contains('rate')) {
      return 'Houve muitas tentativas seguidas. Aguarde um pouco e tente novamente.';
    }
    if (msg.contains('invalid phone')) {
      return 'Numero invalido. Confirme se esta em formato +258XXXXXXXXX.';
    }
    if (msg.contains('invalid login') ||
        msg.contains('wrong password') ||
        msg.contains('invalid credentials')) {
      return 'Senha incorreta. Verifique e tente novamente.';
    }
    return 'Nao conseguimos entrar agora. Verifique o numero e a senha.';
  }

  Map<String, dynamic> _asMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }
    return <String, dynamic>{};
  }

  Map<String, dynamic> _nestedData(Map<String, dynamic> payload) {
    final raw = payload['data'];
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }
    return payload;
  }

  Future<String?> _loginEmailForPhone(String phone) async {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'resolve-login-email',
        body: {'phone': phone},
      );
      final payload = _asMap(response.data);
      final success = payload['success'] != false && response.status < 400;
      final data = _nestedData(payload);
      final email = data['email']?.toString().trim();
      if (success && email != null && email.isNotEmpty) {
        return email;
      }
      // A 404 is a definitive answer from the backend: do not fall back to
      // the synthetic email, otherwise a missing account is reported as a
      // misleading "senha incorreta".
      if (response.status == 404 || !success) {
        return null;
      }
    } catch (_) {
      // Mantem o fallback apenas para falhas de transporte ou indisponibilidade
      // temporaria da function, sem mascarar "conta inexistente" como senha errada.
    }
    return 'phone+$digits@deligo.local';
  }

  Future<void> _handlePhoneLogin() async {
    final phone = _normalizeMozPhone(_phoneController.text);
    final phoneRegex = RegExp(r'^(\+258|258)?[8-9]\d{8}$');
    final password = _passwordController.text.trim();

    if (phone.isEmpty) {
      _showAppSnack('Informe o numero de telefone.');
      return;
    }
    if (!phoneRegex.hasMatch(phone)) {
      _showAppSnack('Numero invalido. Use +258XXXXXXXXX.');
      return;
    }
    if (password.isEmpty) {
      _showAppSnack('Informe a senha para entrar.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final email = await _loginEmailForPhone(phone);
      if (email == null || email.isEmpty) {
        throw const AuthException('user not found');
      }
      final result = await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      if (result.user == null) {
        throw const AuthException('invalid login');
      }
      await TrustSafetyService.instance.logEvent(
        'login_password_success',
        metadata: {'phone': phone},
      );
    } on AuthException catch (e) {
      _showAppSnack(_friendlyLoginMessage(e.message));
    } catch (e) {
      _showAppSnack(_friendlyLoginMessage(e.toString()));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleFieldOtpLogin() async {
    final phone = _normalizeMozPhone(_phoneController.text);
    final phoneRegex = RegExp(r'^(\+258|258)?[8-9]\d{8}$');
    final fullName = _fullNameController.text.trim();
    final code = _otpController.text.replaceAll(RegExp(r'\D'), '');

    if (phone.isEmpty) {
      _showAppSnack('Informe o numero de telefone.');
      return;
    }
    if (!phoneRegex.hasMatch(phone)) {
      _showAppSnack('Numero invalido. Use +258XXXXXXXXX.');
      return;
    }
    if (fullName.length < 3) {
      _showAppSnack('Informe o nome completo usado no convite.');
      return;
    }
    if (code.length != 6) {
      _showAppSnack('Informe o codigo OTP de 6 digitos recebido no convite.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      await PhoneAuthService.instance.verifyOtp(
        phone: phone,
        code: code,
        flow: 'login',
        fullName: fullName,
      );
      if (!mounted) return;
      context.go('/create-password');
    } on AuthException catch (e) {
      _showAppSnack(_friendlyLoginMessage(e.message));
    } catch (e) {
      _showAppSnack(_friendlyLoginMessage(e.toString()));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMarketingBuild = AppRouter.isMarketingBuild;
    final isStaffBuild = AppRouter.isStaffBuild;
    final isSmallPhone =
        MediaQuery.sizeOf(context).width < 370 ||
        MediaQuery.sizeOf(context).height < 700;
    final staffAppName = isMarketingBuild
        ? 'DeliGo Marketing & Publicidade'
        : 'DeliGo Field';
    return Scaffold(
      backgroundColor: const Color(0xFFB40008),
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFFF1717), Color(0xFF8E0006)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _bikeController,
              builder: (context, _) {
                final width = MediaQuery.of(context).size.width;
                final height = MediaQuery.of(context).size.height;
                final dx = (width + 120) * _bikeController.value - 60;
                final dy = height * 0.18;
                return Transform.translate(
                  offset: Offset(dx, dy),
                  child: Icon(
                    Icons.delivery_dining,
                    size: 110,
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                );
              },
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 28, 22, 28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: Column(
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'Powered by DeliGo Triunfal, Lda.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: isSmallPhone ? 16 : 20,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    SizedBox(height: isSmallPhone ? 8 : 18),
                    Icon(
                      Icons.shopping_cart_checkout,
                      size: isSmallPhone ? 54 : 78,
                      color: Colors.white,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'DeliGo',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: isSmallPhone ? 42 : 54,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Bem-vindo à DeliGo',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: isSmallPhone ? 24 : 32,
                        fontWeight: FontWeight.w800,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Sua comida favorita, rápido e fácil!',
                      style: TextStyle(color: Colors.white, fontSize: 17),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: isSmallPhone ? 12 : 22),
                    Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                      elevation: 12,
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          isSmallPhone ? 16 : 28,
                          isSmallPhone ? 16 : 28,
                          isSmallPhone ? 16 : 28,
                          isSmallPhone ? 14 : 22,
                        ),
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: AppColors.primaryRed.withValues(
                                  alpha: 0.1,
                                ),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.lock_outline,
                                size: 58,
                                color: AppColors.primaryRed,
                              ),
                            ),
                            SizedBox(height: isSmallPhone ? 8 : 16),
                            Text(
                              isStaffBuild && _fieldFirstAccess
                                  ? 'Validar convite'
                                  : 'Entrar com senha',
                              style: TextStyle(
                                fontSize: isSmallPhone ? 23 : 30,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primaryRed,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              isStaffBuild
                                  ? _fieldFirstAccess
                                        ? 'Use o nome, telefone e codigo OTP recebidos no convite do Admin.'
                                        : 'Use o telefone convidado pelo Admin e a senha criada no primeiro acesso.'
                                  : 'Use o seu numero e a senha definida no cadastro.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                color: AppColors.darkGray,
                              ),
                            ),
                            SizedBox(height: isSmallPhone ? 12 : 24),
                            TextField(
                              controller: _phoneController,
                              enabled: !_isLoading,
                              keyboardType: TextInputType.phone,
                              decoration: InputDecoration(
                                labelText: 'Número de telefone',
                                hintText: '84XXXXXXX',
                                filled: true,
                                fillColor: Colors.white,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide(color: Colors.black12),
                                ),
                                prefixIcon: const Icon(Icons.phone_android),
                                prefixText: '+258 ',
                              ),
                            ),
                            const SizedBox(height: 16),
                            if (isStaffBuild && _fieldFirstAccess) ...[
                              TextField(
                                controller: _fullNameController,
                                enabled: !_isLoading,
                                textCapitalization: TextCapitalization.words,
                                decoration: InputDecoration(
                                  labelText: 'Nome completo',
                                  hintText: 'Como foi convidado pelo Admin',
                                  filled: true,
                                  fillColor: Colors.white,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  prefixIcon: const Icon(Icons.badge_outlined),
                                ),
                              ),
                              const SizedBox(height: 16),
                              TextField(
                                controller: _otpController,
                                enabled: !_isLoading,
                                keyboardType: TextInputType.number,
                                maxLength: 6,
                                decoration: InputDecoration(
                                  labelText: 'Codigo OTP do convite',
                                  counterText: '',
                                  filled: true,
                                  fillColor: Colors.white,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  prefixIcon: const Icon(Icons.password),
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],
                            if (!isStaffBuild || !_fieldFirstAccess) ...[
                              TextField(
                                controller: _passwordController,
                                enabled: !_isLoading,
                                obscureText: _obscurePassword,
                                decoration: InputDecoration(
                                  labelText: 'Senha',
                                  filled: true,
                                  fillColor: Colors.white,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  prefixIcon: const Icon(Icons.lock),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility
                                          : Icons.visibility_off,
                                    ),
                                    onPressed: () => setState(
                                      () =>
                                          _obscurePassword = !_obscurePassword,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              if (!isStaffBuild)
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    onPressed: _isLoading
                                        ? null
                                        : () => context.go('/forgot-password'),
                                    child: const Text(
                                      'Esqueceu a palavra-passe?',
                                      style: TextStyle(
                                        color: AppColors.primaryRed,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                            const SizedBox(height: 4),
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: ElevatedButton.icon(
                                onPressed: _isLoading
                                    ? null
                                    : isStaffBuild
                                    ? (_fieldFirstAccess
                                          ? _handleFieldOtpLogin
                                          : _handlePhoneLogin)
                                    : _handlePhoneLogin,
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
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                Colors.white,
                                              ),
                                        ),
                                      )
                                    : Icon(
                                        isStaffBuild && _fieldFirstAccess
                                            ? Icons.verified_user
                                            : Icons.login,
                                      ),
                                label: Text(
                                  _isLoading
                                      ? 'A preparar...'
                                      : isStaffBuild && _fieldFirstAccess
                                      ? 'Validar convite'
                                      : 'ENTRAR',
                                ),
                              ),
                            ),
                            if (isStaffBuild) ...[
                              const SizedBox(height: 12),
                              TextButton(
                                onPressed: _isLoading
                                    ? null
                                    : () => setState(() {
                                        _fieldFirstAccess = !_fieldFirstAccess;
                                        _otpController.clear();
                                        _fullNameController.clear();
                                        _passwordController.clear();
                                      }),
                                child: Text(
                                  _fieldFirstAccess
                                      ? 'Ja tenho senha'
                                      : 'Primeiro acesso com OTP',
                                  style: const TextStyle(
                                    color: AppColors.primaryRed,
                                  ),
                                ),
                              ),
                            ],
                            if (!isStaffBuild) ...[
                              const SizedBox(height: 16),
                              Wrap(
                                alignment: WrapAlignment.center,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  const Text('Ainda não tem conta?'),
                                  TextButton(
                                    onPressed: _isLoading
                                        ? null
                                        : () => context.go('/register'),
                                    child: const Text(
                                      'Criar uma Conta Triunfal',
                                      style: TextStyle(
                                        color: AppColors.primaryRed,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: _isLoading
                                      ? null
                                      : () => context.go('/home'),
                                  icon: const Icon(Icons.restaurant_menu),
                                  label: const Text('Continuar como visitante'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.primaryRed,
                                    side: const BorderSide(
                                      color: AppColors.primaryRed,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      '🛡  Acesso seguro  •  Uma conta para todos os serviços',
                      style: TextStyle(color: Colors.white, fontSize: 15),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
