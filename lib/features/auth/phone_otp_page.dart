import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/router/app_router.dart';
import '../../config/theme/app_colors.dart';
import '../../services/auth_session_bootstrap_service.dart';
import '../../services/firebase_analytics_service.dart';
import '../../services/phone_auth_service.dart';
import '../../services/push_notification_service.dart';
import '../../services/trust_safety_service.dart';

class PhoneOtpPage extends StatefulWidget {
  const PhoneOtpPage({
    super.key,
    this.phone,
    this.flow = 'session',
    this.role,
    this.fullName,
  });

  final String? phone;
  final String flow;
  final String? role;
  final String? fullName;

  @override
  State<PhoneOtpPage> createState() => _PhoneOtpPageState();
}

class _PhoneOtpPageState extends State<PhoneOtpPage> {
  final SupabaseClient supabase = Supabase.instance.client;
  late final List<TextEditingController> _digitControllers;
  late final List<FocusNode> _digitFocusNodes;

  Map<String, dynamic>? _profile;
  String? _phone;
  bool _isLoading = true;
  bool _isSending = false;
  bool _isVerifying = false;
  int _cooldownSeconds = 0;
  Timer? _cooldownTimer;
  String? _inlineError;

  bool get _isAuthLoginFlow => widget.flow == 'login';
  bool get _isAuthSignupFlow => widget.flow == 'signup';
  bool get _isAuthResetFlow => widget.flow == 'reset';
  bool get _isStandaloneAuthFlow =>
      _isAuthLoginFlow || _isAuthSignupFlow || _isAuthResetFlow ||
      widget.flow == 'session';

  String _registrationEmailForPhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    return 'phone+$digits@deligo.local';
  }

  @override
  void initState() {
    super.initState();
    _digitControllers = List.generate(6, (_) => TextEditingController());
    _digitFocusNodes = List.generate(6, (_) => FocusNode());
    _bootstrap();
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    for (final controller in _digitControllers) {
      controller.dispose();
    }
    for (final focusNode in _digitFocusNodes) {
      focusNode.dispose();
    }
    super.dispose();
  }

  Future<void> _bootstrap() async {
    if (_isStandaloneAuthFlow) {
      if (!mounted) return;
      setState(() {
        _phone = widget.phone?.trim();
        _isLoading = false;
        _inlineError = (widget.phone?.trim().isEmpty ?? true)
            ? 'Nao encontramos o numero para validar este codigo agora.'
            : null;
      });
      if ((_phone ?? '').isNotEmpty) {
        _startCooldown();
      }
      return;
    }

    final user = supabase.auth.currentUser;
    if (user == null) {
      if (mounted) context.go('/login');
      return;
    }

    try {
      final profile = await supabase
          .from('profiles')
          .select('role, phone, kyc_status, settings')
          .eq('id', user.id)
          .maybeSingle();

      final resolvedProfile = profile == null
          ? null
          : Map<String, dynamic>.from(profile);
      // During a phone change the profile still carries the old, verified
      // number until this OTP succeeds. The explicitly supplied number is the
      // pending Auth phone and must take precedence for this secure flow.
      final pendingPhone = widget.phone?.trim();
      final resolvedPhone = pendingPhone?.isNotEmpty == true
          ? pendingPhone!
          : resolvedProfile?['phone']?.toString().trim().isNotEmpty == true
          ? resolvedProfile!['phone'].toString().trim()
          : user.phone?.trim().isNotEmpty == true
          ? user.phone!.trim()
          : (user.userMetadata?['phone'] as String?)?.trim();

      if (!mounted) return;
      setState(() {
        _profile = resolvedProfile;
        _phone = resolvedPhone;
        _isLoading = false;
        _inlineError = null;
      });

      final needsPhoneVerification = AppRouter.requiresPhoneVerification(
        profile: resolvedProfile,
        user: user,
      );
      if (!needsPhoneVerification) {
        final preparedProfile = await AuthSessionBootstrapService.instance
            .prepareAuthenticatedUser(user);
        if (!mounted) return;
        _profile = preparedProfile ?? resolvedProfile;
        _completeFlow(user: user, profile: _profile);
      }
    } catch (error) {
      debugPrint('PhoneOtpPage._bootstrap error: $error');
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSnack('Nao conseguimos preparar a verificacao por SMS agora.');
    }
  }

  Future<void> _resendCode() async {
    if (_phone == null || _phone!.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    try {
      if (_isStandaloneAuthFlow) {
        await PhoneAuthService.instance.requestOtp(
          phone: _phone!,
          flow: widget.flow,
          role: widget.role,
          fullName: widget.fullName,
        );
      }
      _startCooldown();
      _showSnack(
        'Codigo reenviado. Veja o SMS e continue daqui.',
        success: true,
      );
    } on AuthException catch (e) {
      setState(() => _inlineError = _friendlyAuthMessage(e.message));
    } catch (e) {
      setState(() => _inlineError = _friendlyAuthMessage(e.toString()));
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _verifyCode() async {
    final code = _otpCode;
    if (code.length < 6) {
      setState(() => _inlineError = 'Informe o codigo SMS com os 6 digitos.');
      return;
    }
    if (_phone == null || _phone!.isEmpty) {
      setState(
        () => _inlineError =
            'Nao encontramos um telefone valido para concluir a verificacao.',
      );
      return;
    }
    setState(() {
      _isVerifying = true;
      _inlineError = null;
    });

    try {
      final User user;
      final Map<String, dynamic>? profile;
      if (_isStandaloneAuthFlow) {
        if (_isAuthResetFlow) {
          await PhoneAuthService.instance.verifyPasswordResetOtp(
            phone: _phone!,
            code: code,
          );
          if (!mounted) return;
          _clearOtpInputs();
          context.go('/reset-password');
          return;
        }
        final result = await PhoneAuthService.instance.verifyOtp(
          phone: _phone!,
          flow: widget.flow,
          code: code,
          role: widget.role,
          fullName: widget.fullName,
        );
        user = result.user;
        profile = result.profile;
      } else {
        throw const AuthException('Fluxo de verificacao SMS invalido.');
      }

      try {
        await PushNotificationService().initialize();
        await PushNotificationService().registerFcmToken();
      } catch (error) {
        debugPrint('PhoneOtpPage.pushSetup error: $error');
      }
      // Device registration and analytics are useful observability signals,
      // but an outage in either one must never reject a valid SMS OTP.
      try {
        await TrustSafetyService.instance.registerCurrentDevice();
        await FirebaseAnalyticsService.instance.setUser(
          userId: user.id,
          role: profile?['role']?.toString() ?? 'client',
        );
        await TrustSafetyService.instance.logEvent(
          _isAuthSignupFlow ? 'signup_verified' : 'login_verified',
          metadata: {
            'role': profile?['role']?.toString() ?? user.userMetadata?['role'],
          },
        );
        if (_isAuthSignupFlow) {
          await TrustSafetyService.instance.recordRegistrationAttempt(
            email: _registrationEmailForPhone(_phone!),
            phone: _phone!,
            result: 'completed',
            reason: 'signup_verified',
            role: profile?['role']?.toString() ?? widget.role,
          );
        }
      } catch (error) {
        debugPrint('PhoneOtpPage.postVerificationTelemetry error: $error');
      }

      if (!mounted) return;
      _profile = profile;
      _clearOtpInputs();
      _showSnack('Telefone validado. Ja pode seguir.', success: true);
      _completeFlow(user: user, profile: profile);
    } on AuthException catch (e) {
      setState(() => _inlineError = _friendlyAuthMessage(e.message));
      _clearOtpInputs();
      _focusDigit(0);
    } catch (e) {
      setState(() => _inlineError = _friendlyAuthMessage(e.toString()));
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  void _completeFlow({required User user, Map<String, dynamic>? profile}) {
    final effectiveProfile = profile ?? _profile;
    if (_isAuthSignupFlow) {
      context.go('/create-password');
      return;
    }
    if (_isAuthResetFlow) {
      context.go('/reset-password');
      return;
    }
    final destination = AppRouter.destinationForRole(
      effectiveProfile?['role']?.toString() ?? 'client',
      kycStatus: effectiveProfile?['kyc_status']?.toString(),
      emailConfirmed: true,
      phoneVerificationRequired: false,
    );
    context.go(destination);
  }

  Future<void> _returnToLogin() async {
    // OTP sign-in/reset can create a short-lived session.  Leaving the flow
    // must explicitly close it; otherwise GoRouter treats /login as public
    // while an authenticated user is present and sends them to a dashboard.
    AuthRefreshNotifier.markIntentionalSignOut();
    await supabase.auth.signOut();
    if (!mounted) return;
    context.go('/login');
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    if (!mounted) return;
    setState(() => _cooldownSeconds = 45);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_cooldownSeconds <= 1) {
        timer.cancel();
        setState(() => _cooldownSeconds = 0);
        return;
      }
      setState(() => _cooldownSeconds -= 1);
    });
  }

  String _friendlyAuthMessage(String rawMessage) {
    final normalized = rawMessage.toLowerCase();
    if (normalized.contains('expired')) {
      return 'O codigo expirou. Peca um novo SMS para continuar.';
    }
    if (normalized.contains('invalid') || normalized.contains('token')) {
      return 'Codigo invalido. Confirme os 6 digitos recebidos por SMS.';
    }
    if (normalized.contains('too many') || normalized.contains('rate')) {
      return 'Houve muitas tentativas seguidas. Aguarde um pouco e tente novamente.';
    }
    if (normalized.contains('sender id') &&
        (normalized.contains('not approved') ||
            normalized.contains('not authorized') ||
            normalized.contains('accessible'))) {
      return 'O envio de SMS da MozeSMS ainda nao esta autorizado para esta conta. Ative um Sender ID aprovado no painel da MozeSMS.';
    }
    if (normalized.contains('auth_invalid') ||
        normalized.contains('invalid token format')) {
      return 'A integracao da MozeSMS nao esta autenticada corretamente. Verifique as credenciais da conta.';
    }
    if ((normalized.contains('sms') && normalized.contains('disabled')) ||
        normalized.contains('phone provider') ||
        normalized.contains('twilio') ||
        normalized.contains('messagebird') ||
        normalized.contains('vonage') ||
        normalized.contains('mozesms')) {
      return 'O envio de SMS nao esta configurado corretamente. Verifique a integracao da MozeSMS.';
    }
    if (normalized.contains('user not found')) {
      return 'Ainda nao encontramos uma conta com este numero.';
    }
    return 'Nao foi possivel concluir a verificacao por SMS agora.';
  }

  String get _otpCode =>
      _digitControllers.map((controller) => controller.text).join();

  void _clearOtpInputs() {
    for (final controller in _digitControllers) {
      controller.clear();
    }
  }

  void _focusDigit(int index) {
    if (index < 0 || index >= _digitFocusNodes.length) return;
    _digitFocusNodes[index].requestFocus();
  }

  void _onDigitChanged(int index, String value) {
    if (value.length > 1) {
      final digitsOnly = value.replaceAll(RegExp(r'\D'), '');
      for (var i = 0; i < _digitControllers.length; i++) {
        _digitControllers[i].text = i < digitsOnly.length ? digitsOnly[i] : '';
      }
      setState(() => _inlineError = null);
      if (digitsOnly.length >= _digitControllers.length) {
        FocusScope.of(context).unfocus();
        if (!_isVerifying) {
          _verifyCode();
        }
      } else {
        _focusDigit(digitsOnly.length.clamp(0, _digitFocusNodes.length - 1));
      }
      return;
    }

    setState(() => _inlineError = null);
    if (value.isEmpty && index > 0) {
      _focusDigit(index - 1);
      return;
    }
    if (value.isNotEmpty) {
      if (index < _digitFocusNodes.length - 1) {
        _focusDigit(index + 1);
      } else {
        FocusScope.of(context).unfocus();
        if (_otpCode.length == _digitControllers.length && !_isVerifying) {
          _verifyCode();
        }
      }
    }
  }

  Widget _buildOtpDigitBox(int index) {
    final hasError = _inlineError != null && _inlineError!.isNotEmpty;
    return SizedBox(
      width: 46,
      child: TextField(
        controller: _digitControllers[index],
        focusNode: _digitFocusNodes[index],
        enabled: !_isVerifying && _phone != null,
        keyboardType: TextInputType.number,
        textInputAction: index == _digitControllers.length - 1
            ? TextInputAction.done
            : TextInputAction.next,
        autofillHints: index == 0 ? const [AutofillHints.oneTimeCode] : null,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(1),
        ],
        decoration: InputDecoration(
          counterText: '',
          filled: true,
          fillColor: _isVerifying ? const Color(0xFFF5F5F5) : Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
              color: hasError ? AppColors.alertRed : const Color(0xFFD9D9D9),
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
              color: hasError ? AppColors.alertRed : const Color(0xFFD9D9D9),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
              color: hasError ? AppColors.alertRed : AppColors.primaryRed,
              width: 2,
            ),
          ),
        ),
        onChanged: (value) => _onDigitChanged(index, value),
        onTap: () {
          _digitControllers[index].selection = TextSelection(
            baseOffset: 0,
            extentOffset: _digitControllers[index].text.length,
          );
        },
      ),
    );
  }

  void _showSnack(String message, {bool success = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: success
            ? AppColors.successGreen
            : AppColors.primaryRed,
        content: Text(message),
      ),
    );
  }

  String _maskedPhone() {
    final phone = _phone ?? '';
    if (phone.length < 4) return phone;
    final suffix = phone.substring(phone.length - 3);
    return '${phone.substring(0, phone.length - 3).replaceAll(RegExp(r'\d'), '*')}$suffix';
  }

  @override
  Widget build(BuildContext context) {
    final title = _isAuthSignupFlow
        ? 'Confirmar cadastro'
        : _isAuthResetFlow
        ? 'Recuperar senha'
        : _isAuthLoginFlow
        ? 'Confirmar entrada'
        : 'Verificar telefone';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: AppColors.primaryRed,
        foregroundColor: AppColors.cleanWhite,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    elevation: 8,
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Icon(
                            Icons.sms_outlined,
                            size: 68,
                            color: AppColors.primaryRed,
                          ),
                          const SizedBox(height: 18),
                          Text(
                            _isAuthSignupFlow
                                ? 'Codigo de ativacao'
                                : _isAuthResetFlow
                                ? 'Codigo de recuperacao'
                                : _isAuthLoginFlow
                                ? 'Codigo de acesso'
                                : 'Codigo SMS',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _phone == null || _phone!.isEmpty
                                ? 'Nao encontramos um numero de telefone para esta conta.'
                                : 'Enviamos um codigo para ${_maskedPhone()}. Se o Android suportar, o codigo pode aparecer automaticamente.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppColors.neutralGray,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'Digite os 6 digitos recebidos',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.neutralGray,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: List.generate(
                              _digitControllers.length,
                              _buildOtpDigitBox,
                            ),
                          ),
                          const SizedBox(height: 10),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 180),
                            child: _inlineError == null || _inlineError!.isEmpty
                                ? const SizedBox(height: 20)
                                : Container(
                                    key: ValueKey(_inlineError),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFF1F1),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: const Color(0xFFFFD4D4),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.error_outline,
                                          color: AppColors.alertRed,
                                          size: 18,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            _inlineError!,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              color: AppColors.alertRed,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                          ),
                          const SizedBox(height: 18),
                          SizedBox(
                            height: 50,
                            child: ElevatedButton.icon(
                              onPressed: _isVerifying || _phone == null
                                  ? null
                                  : _verifyCode,
                              icon: _isVerifying
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
                                  : const Icon(Icons.verified_outlined),
                              label: Text(
                                _isVerifying
                                    ? 'A validar...'
                                    : 'Confirmar codigo',
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primaryRed,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextButton.icon(
                            onPressed:
                                _cooldownSeconds > 0 ||
                                    _isSending ||
                                    _phone == null
                                ? null
                                : _resendCode,
                            icon: _isSending
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.refresh),
                            label: Text(
                              _cooldownSeconds > 0
                                  ? 'Reenviar em ${_cooldownSeconds}s'
                                  : 'Reenviar codigo',
                            ),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton(
                            onPressed: _isVerifying ? null : _returnToLogin,
                            child: Text(
                              _isAuthSignupFlow ? 'Voltar ao inicio' : 'Voltar',
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
