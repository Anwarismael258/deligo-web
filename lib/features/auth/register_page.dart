import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/theme/app_colors.dart';
import '../../services/phone_auth_service.dart';
import '../../services/trust_safety_service.dart';
import '../../shared/utils/mozambique_wallet_validation.dart';

enum Role { client, restaurant, courier }

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key, this.initialRole});

  final String? initialRole;

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final nameController = TextEditingController();
  final phoneController = TextEditingController();

  Role? selectedRole;
  bool acceptedTerms = false;
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    selectedRole = _roleFromName(widget.initialRole);
    if (phoneController.text.trim().isEmpty) {
      phoneController.text = '+258';
      phoneController.selection = TextSelection.collapsed(
        offset: phoneController.text.length,
      );
    }
    phoneController.addListener(_ensurePhonePrefix);
  }

  @override
  void dispose() {
    phoneController.removeListener(_ensurePhonePrefix);
    nameController.dispose();
    phoneController.dispose();
    super.dispose();
  }

  void _ensurePhonePrefix() {
    final raw = phoneController.text;
    if (raw.startsWith('+258')) return;
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    final localDigits = digits.startsWith('258') ? digits.substring(3) : digits;
    final updated = '+258$localDigits';
    phoneController.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: updated.length),
    );
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

  String _registrationEmailForPhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    return 'phone+$digits@deligo.local';
  }

  String _roleLabel(Role role) {
    switch (role) {
      case Role.client:
        return 'CLIENTE';
      case Role.restaurant:
        return 'RESTAURANTE';
      case Role.courier:
        return 'ESTAFETA';
    }
  }

  String _roleDescription(Role? role) {
    switch (role) {
      case Role.client:
        return 'Confirme o numero por SMS e crie a sua senha para entrar.';
      case Role.restaurant:
        return 'Confirme o numero por SMS, crie a sua senha e depois conclua os dados da loja e da validacao no onboarding.';
      case Role.courier:
        return 'Confirme o numero por SMS, crie a sua senha e depois conclua os seus dados e documentos no onboarding.';
      case null:
        return 'Escolha o tipo de conta para continuar.';
    }
  }

  String _roleName(Role role) => role.toString().split('.').last;

  Role? _roleFromName(String? value) {
    switch (value?.trim().toLowerCase()) {
      case 'client':
      case 'cliente':
        return Role.client;
      case 'restaurant':
      case 'restaurante':
        return Role.restaurant;
      case 'courier':
      case 'estafeta':
      case 'driver':
        return Role.courier;
      default:
        return null;
    }
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
    if (normalized.contains('already') || normalized.contains('registered')) {
      return 'Este numero ja esta registado. Use "Entrar" para receber o codigo SMS ou cadastre outro numero.';
    }
    if (normalized.contains('too many') || normalized.contains('rate')) {
      return 'Muitas tentativas seguidas. Aguarde um pouco e tente novamente.';
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
    if (normalized.contains('invalid phone')) {
      return 'Numero de telefone invalido. Use +258XXXXXXXXX.';
    }
    return 'Nao foi possivel enviar o codigo SMS agora.';
  }

  Future<void> register() async {
    final fullName = nameController.text.trim();
    final phone = _normalizeMozPhone(phoneController.text.trim());
    final phoneRegex = RegExp(r'^(\+258|258)?[8-9]\d{8}$');

    if (fullName.isEmpty) {
      _showAppSnack('Informe o nome do perfil.');
      return;
    }
    if (phone.isEmpty || !phoneRegex.hasMatch(phone)) {
      _showAppSnack('Numero de telefone invalido. Use +258XXXXXXXXX.');
      return;
    }
    if (MozambiqueWalletValidation.inferMethod(phone) ==
        MozambiqueWalletMethod.mkesh) {
      _showAppSnack(
        'Neste momento aceitamos apenas numeros M-Pesa (84/85) ou e-Mola (86/87).',
      );
      return;
    }
    if (selectedRole == null) {
      _showAppSnack('Escolha um perfil.');
      return;
    }
    if (!acceptedTerms) {
      _showAppSnack('Aceite os Termos e Condicoes.');
      return;
    }

    final roleName = _roleName(selectedRole!);
    final registrationEmail = _registrationEmailForPhone(phone);
    final registrationGuard = await TrustSafetyService.instance
        .checkRegistrationGuard(email: registrationEmail, phone: phone);

    if (registrationGuard['device_blocked'] == true) {
      await TrustSafetyService.instance.recordRegistrationAttempt(
        email: registrationEmail,
        phone: phone,
        result: 'blocked',
        reason: 'too_many_attempts',
        role: roleName,
      );
      _showAppSnack(
        'Detetamos varias tentativas neste dispositivo. Tente mais tarde.',
      );
      return;
    }
    // A mesma conta profissional pode retomar o fluxo por OTP (por exemplo,
    // após uma interrupção no onboarding/KYC). O backend continua a validar
    // que a função solicitada corresponde à função já registada.
    if (registrationGuard['phone_exists'] == true &&
        selectedRole == Role.client) {
      await TrustSafetyService.instance.recordRegistrationAttempt(
        email: registrationEmail,
        phone: phone,
        result: 'failed',
        reason: 'phone_exists',
        role: roleName,
      );
      _showAppSnack(
        'Ja existe conta com este numero. Use "Entrar" para receber o codigo SMS ou cadastre outro numero.',
      );
      return;
    }

    setState(() => isLoading = true);
    try {
      await PhoneAuthService.instance.requestOtp(
        phone: phone,
        flow: 'signup',
        role: roleName,
        fullName: fullName,
      );

      await TrustSafetyService.instance.recordRegistrationAttempt(
        email: registrationEmail,
        phone: phone,
        result: 'otp_sent',
        reason: 'signup_otp_sent',
        role: roleName,
      );

      if (!mounted) return;
      context.go(
        '/phone-otp?flow=signup&phone=${Uri.encodeQueryComponent(phone)}'
        '&role=${Uri.encodeQueryComponent(roleName)}'
        '&name=${Uri.encodeQueryComponent(fullName)}',
      );
    } on AuthException catch (e) {
      await TrustSafetyService.instance.recordRegistrationAttempt(
        email: registrationEmail,
        phone: phone,
        result: 'failed',
        reason: e.message,
        role: roleName,
      );
      _showAppSnack(_friendlyOtpRequestMessage(e.message));
    } catch (e) {
      await TrustSafetyService.instance.recordRegistrationAttempt(
        email: registrationEmail,
        phone: phone,
        result: 'failed',
        reason: e.toString(),
        role: roleName,
      );
      _showAppSnack(_friendlyOtpRequestMessage(e.toString()));
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _showTermsDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          padding: const EdgeInsets.all(16),
          constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'TERMOS E CONDICOES',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'DELIGO · VERSÃO 1.0 · 19/09/2026',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryRed,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSectionTitle('1. SOBRE A PLATAFORMA'),
                      _buildSectionText(
                        'A Deligo Entregas conecta clientes, restaurantes parceiros e estafetas independentes.',
                      ),
                      _buildSectionTitle('2. ACEITACAO DOS TERMOS'),
                      _buildSectionText(
                        'Ao criar conta, o utilizador declara que leu, compreendeu e concorda com os termos.',
                      ),
                      _buildSectionTitle('3. ELEGIBILIDADE'),
                      _buildSectionText(
                        '- Ter pelo menos 18 anos\n- Fornecer informacoes verdadeiras\n- Possuir telefone valido em Mocambique\n- Cumprir KYC quando aplicavel\n- Aceitar as regras de pedidos, pagamentos, carteira, cancelamentos e reembolsos',
                      ),
                      _buildSectionTitle('4. PAGAMENTOS E CARTEIRA'),
                      _buildSectionText(
                        'Os depósitos e levantamentos têm taxa operacional de 3%, apresentada antes da confirmação. Uma operação pendente só é concluída quando aparecer como confirmada no histórico. M-Pesa, e-Mola e outros parceiros podem aplicar os seus próprios prazos.',
                      ),
                      _buildSectionTitle('5. SUPORTE E DADOS'),
                      _buildSectionText(
                        'A DeliGo pode utilizar dados de conta, pedidos, localização e pagamentos para executar o serviço, prestar suporte, prevenir fraude e cumprir obrigações legais, conforme a Política de Privacidade. Contacto: +258 84 113 0015.',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          this.context.push('/privacy');
                        },
                        child: const Text('Privacidade'),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          this.context.push('/refund-policy');
                        },
                        child: const Text('Reembolsos'),
                      ),
                    ],
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Fechar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: AppColors.darkGray,
        ),
      ),
    );
  }

  Widget _buildSectionText(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        color: AppColors.neutralGray,
        height: 1.4,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 28, 22, 28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: Column(
                  children: [
                    const Text(
                      'Powered by DeliGo Triunfal, Lda.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Icon(
                      Icons.shopping_cart_checkout,
                      size: 78,
                      color: Colors.white,
                    ),
                    const Text(
                      'DeliGo',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 54,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Crie a sua Conta Triunfal',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Uma conta para todos os serviços DeliGo',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 22),
                    Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                      elevation: 12,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(28, 28, 28, 22),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextField(
                              enabled: !isLoading,
                              controller: nameController,
                              decoration: InputDecoration(
                                labelText: selectedRole == Role.restaurant
                                    ? 'Nome do restaurante'
                                    : selectedRole == Role.courier
                                    ? 'Nome do estafeta'
                                    : 'Nome completo',
                                filled: true,
                                fillColor: Colors.white,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                prefixIcon: const Icon(Icons.person),
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              enabled: !isLoading,
                              controller: phoneController,
                              keyboardType: TextInputType.phone,
                              decoration: InputDecoration(
                                labelText: 'Telemovel principal',
                                hintText: '+258XXXXXXXXX',
                                helperText:
                                    'Usaremos este numero para enviar o OTP do cadastro.',
                                filled: true,
                                fillColor: Colors.white,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                prefixIcon: const Icon(Icons.phone),
                              ),
                            ),
                            const SizedBox(height: 20),
                            const Text(
                              'Tipo de conta',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: Role.values.map((role) {
                                final selected = selectedRole == role;
                                return ChoiceChip(
                                  label: Text(_roleLabel(role)),
                                  selected: selected,
                                  onSelected: isLoading
                                      ? null
                                      : (_) =>
                                            setState(() => selectedRole = role),
                                  selectedColor: AppColors.primaryRed
                                      .withValues(alpha: 0.14),
                                  labelStyle: TextStyle(
                                    color: selected
                                        ? AppColors.primaryRed
                                        : AppColors.darkGray,
                                    fontWeight: FontWeight.w700,
                                  ),
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF5F5),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                _roleDescription(selectedRole),
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.neutralGray,
                                  height: 1.35,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Checkbox(
                                  value: acceptedTerms,
                                  onChanged: isLoading
                                      ? null
                                      : (value) => setState(
                                          () => acceptedTerms = value ?? false,
                                        ),
                                ),
                                Expanded(
                                  child: Wrap(
                                    children: [
                                      const Text('Li e aceito os '),
                                      GestureDetector(
                                        onTap: isLoading
                                            ? null
                                            : _showTermsDialog,
                                        child: const Text(
                                          'Termos e Condicoes',
                                          style: TextStyle(
                                            color: AppColors.primaryRed,
                                            fontWeight: FontWeight.bold,
                                            decoration:
                                                TextDecoration.underline,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: ElevatedButton.icon(
                                onPressed: isLoading ? null : register,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primaryRed,
                                  foregroundColor: Colors.white,
                                ),
                                icon: isLoading
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
                                    : const Icon(Icons.sms),
                                label: Text(
                                  isLoading
                                      ? 'A enviar codigo...'
                                      : 'Continuar com SMS',
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text('Ja tem conta?'),
                                TextButton(
                                  onPressed: isLoading
                                      ? null
                                      : () => context.go('/login'),
                                  child: const Text(
                                    'Entrar',
                                    style: TextStyle(
                                      color: AppColors.primaryRed,
                                    ),
                                  ),
                                ),
                              ],
                            ),
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
