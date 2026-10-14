import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/theme/app_colors.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  static const completedStorageKey = 'deligo_onboarding_completed_v2';

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  String _language = 'pt';

  Future<void> _start() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(OnboardingPage.completedStorageKey, true);
    if (!mounted) return;
    HapticFeedback.lightImpact();
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final isPortuguese = _language == 'pt';
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F5),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.topRight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.borderGray),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _LanguageChoice(
                          label: 'PT',
                          selected: _language == 'pt',
                          onTap: () => setState(() => _language = 'pt'),
                        ),
                        const Text(
                          '|',
                          style: TextStyle(color: Colors.black38),
                        ),
                        _LanguageChoice(
                          label: 'EN',
                          selected: _language == 'en',
                          onTap: () => setState(() => _language = 'en'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Center(
                child: Image.asset(
                  'assets/1000162336.png',
                  height: 76,
                  fit: BoxFit.contain,
                  semanticLabel: 'Logótipo DeliGo',
                ),
              ),
              const SizedBox(height: 26),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        Container(
                          height: 220,
                          width: double.infinity,
                          constraints: const BoxConstraints(maxWidth: 390),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFE5DE),
                            borderRadius: BorderRadius.circular(32),
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.delivery_dining_rounded,
                              size: 132,
                              color: AppColors.primaryRed,
                            ),
                          ),
                        ),
                        const SizedBox(height: 30),
                        Text(
                          isPortuguese ? 'Comida perto de si' : 'Food near you',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.darkGray,
                            fontSize: 30,
                            height: 1.15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 390),
                          child: Text(
                            isPortuguese
                                ? 'Peça aos seus restaurantes favoritos e acompanhe a entrega em tempo real.'
                                : 'Order from your favourite restaurants and track your delivery in real time.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: AppColors.neutralGray,
                              fontSize: 16,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: 54,
                child: ElevatedButton(
                  onPressed: _start,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryRed,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    isPortuguese ? 'Começar' : 'Get started',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _LegalLink(
                    label: isPortuguese
                        ? 'Termos e Condições'
                        : 'Terms & Conditions',
                    onTap: () => context.push('/terms'),
                  ),
                  const Text('  ·  ', style: TextStyle(color: Colors.black38)),
                  _LegalLink(
                    label: isPortuguese ? 'Privacidade' : 'Privacy',
                    onTap: () => context.push('/privacy'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LanguageChoice extends StatelessWidget {
  const _LanguageChoice({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(14),
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? AppColors.primaryRed : AppColors.neutralGray,
          fontSize: 12,
          fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
        ),
      ),
    ),
  );
}

class _LegalLink extends StatelessWidget {
  const _LegalLink({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.primaryRed,
          fontSize: 13,
          decoration: TextDecoration.underline,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}
