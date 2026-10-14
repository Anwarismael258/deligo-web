import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../config/theme/app_colors.dart';
import '../../services/app_language_controller.dart';
import '../../services/app_strings.dart';

class LanguageSetupPage extends StatefulWidget {
  const LanguageSetupPage({super.key});

  @override
  State<LanguageSetupPage> createState() => _LanguageSetupPageState();
}

class _LanguageSetupPageState extends State<LanguageSetupPage> {
  String _selected = 'pt';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _selected = context.read<AppLanguageController>().languageCode;
  }

  @override
  Widget build(BuildContext context) {
    String t(String key) => AppStrings.of(context, key);
    final languageController = context.read<AppLanguageController>();
    final navigator = GoRouter.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFFFFF7F4),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              Text(
                t('choose_language'),
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  color: AppColors.darkGray,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                t('choose_language_desc'),
                style: const TextStyle(
                  color: AppColors.neutralGray,
                  fontSize: 15,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 28),
              _buildLanguageTile(
                code: 'pt',
                title: t('portuguese'),
                subtitle: 'Portuguese',
                icon: Icons.flag_circle_rounded,
              ),
              const SizedBox(height: 12),
              _buildLanguageTile(
                code: 'en',
                title: t('english'),
                subtitle: 'English',
                icon: Icons.language_rounded,
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => navigator.push('/deligo-ai'),
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Pergunte à DeliGo IA'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    await languageController.setLanguage(_selected);
                    if (!mounted) return;
                    navigator.go('/onboarding');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryRed,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(t('continue')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLanguageTile({
    required String code,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final selected = _selected == code;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => setState(() => _selected = code),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? AppColors.primaryRed
                : AppColors.borderGray.withValues(alpha: 0.8),
            width: selected ? 2 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppColors.primaryRed.withValues(alpha: 0.12),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ]
              : [],
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: AppColors.primaryRed.withValues(alpha: 0.1),
              child: Icon(icon, color: AppColors.primaryRed),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(color: AppColors.neutralGray),
                  ),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected ? AppColors.primaryRed : AppColors.neutralGray,
            ),
          ],
        ),
      ),
    );
  }
}
