import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/theme/app_colors.dart';
import '../../config/router/app_router.dart';
import '../../services/account_deletion_service.dart';
import '../../services/app_language_controller.dart';
import '../../services/app_strings.dart';
import '../../services/sound_controller.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final supabase = Supabase.instance.client;
  Map<String, dynamic> _settings = {};
  String _language = 'pt';
  bool _darkTheme = false;
  bool _soundEnabled = true;
  String _voiceMode = 'important_only';
  String _currency = 'MZN';
  bool _saving = false;
  bool _requestingDeletion = false;
  String _lastError = '';

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    try {
      final res = await supabase
          .from('profiles')
          .select('settings')
          .eq('id', user.id)
          .maybeSingle();
      if (res != null) {
        final settings =
            (res['settings'] as Map?)?.cast<String, dynamic>() ?? {};
        _settings = Map<String, dynamic>.from(settings);
        _language = settings['language'] ?? 'pt';
        _darkTheme = settings['dark_theme'] ?? false;
        _soundEnabled = settings['sound_enabled'] ?? true;
        _voiceMode = settings['voice_mode'] ?? 'important_only';
        _currency = settings['currency'] ?? 'MZN';
      }
    } catch (_) {
      final meta = user.userMetadata ?? {};
      final settings =
          (meta['settings'] as Map?)?.cast<String, dynamic>() ?? {};
      _settings = Map<String, dynamic>.from(settings);
      _language = settings['language'] ?? 'pt';
      _darkTheme = settings['dark_theme'] ?? false;
      _soundEnabled = settings['sound_enabled'] ?? true;
      _voiceMode = settings['voice_mode'] ?? 'important_only';
      _currency = settings['currency'] ?? 'MZN';
    }
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    final languageController = context.read<AppLanguageController>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      _lastError = '';
      final nextSettings = Map<String, dynamic>.from(_settings);
      nextSettings['language'] = _language;
      nextSettings['dark_theme'] = _darkTheme;
      nextSettings['sound_enabled'] = _soundEnabled;
      nextSettings['voice_mode'] = _voiceMode;
      nextSettings['currency'] = _currency;
      await supabase
          .from('profiles')
          .update({
            'settings': nextSettings,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', user.id);
      _settings = nextSettings;
      await languageController.setLanguage(_language, persistRemote: false);
      await SoundController.instance.setEnabled(_soundEnabled, persist: false);
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(AppStrings.of(context, 'settings_saved'))),
        );
      }
    } catch (e) {
      _lastError = e.toString();
      try {
        final nextSettings = Map<String, dynamic>.from(_settings);
        nextSettings['language'] = _language;
        nextSettings['dark_theme'] = _darkTheme;
        nextSettings['sound_enabled'] = _soundEnabled;
        nextSettings['voice_mode'] = _voiceMode;
        nextSettings['currency'] = _currency;
        await supabase.auth.updateUser(
          UserAttributes(data: {'settings': nextSettings}),
        );
        _settings = nextSettings;
      } catch (_) {}

      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              _lastError.isNotEmpty
                  ? 'Salvo parcialmente. Ajuste a base para address/settings.'
                  : AppStrings.of(context, 'settings_saved'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _signOutAll() async {
    try {
      AuthRefreshNotifier.markIntentionalSignOut();
      await supabase.auth.signOut(scope: SignOutScope.global);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.of(context, 'sessions_closed'))),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ocorreu um erro. Tente novamente.')),
        );
      }
    }
  }

  Future<void> _requestAccountDeletion() async {
    String t(String key) => AppStrings.of(context, key);
    final messenger = ScaffoldMessenger.of(context);
    final deletionService = AccountDeletionService();
    late final AccountDeletionPreview preview;
    try {
      preview = await deletionService.previewDeletion();
    } catch (error) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
        );
      }
      return;
    }
    if (!preview.canDelete) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              preview.message ?? 'Não é possível eliminar a conta agora.',
            ),
          ),
        );
      }
      return;
    }
    final confirmationController = TextEditingController();
    final reasonController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(t('delete_account_dialog_title')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(t('delete_account_dialog_body')),
              if (preview.transferableAmount > 0) ...[
                const SizedBox(height: 10),
                Text(preview.confirmationDisclosure),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: reasonController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: t('delete_account_reason_label'),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmationController,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: t('delete_account_confirm_label'),
                  hintText: t('delete_account_confirm_hint'),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(t('cancel')),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.alertRed,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: Text(t('delete_account')),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      confirmationController.dispose();
      reasonController.dispose();
      return;
    }

    final confirmationText = confirmationController.text.trim().toUpperCase();
    final reason = reasonController.text.trim();
    confirmationController.dispose();
    reasonController.dispose();

    if (confirmationText != 'DELETE') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t('delete_account_dialog_body'))),
        );
      }
      return;
    }

    setState(() => _requestingDeletion = true);
    try {
      final result = await deletionService.requestDeletion(
        confirmationText: confirmationText,
        reason: reason.isEmpty ? null : reason,
      );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            result.message.isNotEmpty
                ? result.message
                : t('delete_account_sent'),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e.toString().replaceFirst('Exception: ', '').trim().isNotEmpty
                ? e.toString().replaceFirst('Exception: ', '').trim()
                : 'Ocorreu um erro. Tente novamente.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _requestingDeletion = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _buildCompactRestaurantSettings();
    /*
    String t(String key) => AppStrings.of(context, key);
    final email = supabase.auth.currentUser?.email ?? '';
    return Scaffold(
      appBar: AppBar(
        title: Text(t('settings')),
        backgroundColor: AppColors.primaryRed,
        foregroundColor: AppColors.cleanWhite,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildHeader(email, t),
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t('preferences'),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _language,
                    decoration: InputDecoration(
                      labelText: t('language'),
                      prefixIcon: const Icon(Icons.language),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'pt',
                        child: Text(t('portuguese')),
                      ),
                      DropdownMenuItem(value: 'en', child: Text(t('english'))),
                    ],
                    onChanged: (v) async {
                      final next = v ?? 'pt';
                      setState(() => _language = next);
                      await context.read<AppLanguageController>().setLanguage(
                        next,
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _currency,
                    decoration: InputDecoration(
                      labelText: t('currency'),
                      prefixIcon: const Icon(Icons.payments),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'MZN', child: Text('MZN')),
                    ],
                    onChanged: (v) => setState(() => _currency = v ?? 'MZN'),
                  ),
                  SwitchListTile(
                    value: _darkTheme,
                    onChanged: (v) => setState(() => _darkTheme = v),
                    title: Text(t('dark_theme')),
                  ),
                  SwitchListTile(
                    value: _soundEnabled,
                    onChanged: (v) => setState(() => _soundEnabled = v),
                    title: Text(t('app_sounds')),
                    subtitle: Text(t('sound_desc')),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _voiceMode,
                    decoration: InputDecoration(
                      labelText: t('voice_mode'),
                      helperText: t('voice_mode_desc'),
                      prefixIcon: const Icon(Icons.record_voice_over_outlined),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'full',
                        child: Text(t('voice_full')),
                      ),
                      DropdownMenuItem(
                        value: 'important_only',
                        child: Text(t('voice_important_only')),
                      ),
                      DropdownMenuItem(
                        value: 'off',
                        child: Text(t('voice_off')),
                      ),
                    ],
                    onChanged: (v) =>
                        setState(() => _voiceMode = v ?? 'important_only'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Legal',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.description_outlined),
                    title: const Text('Termos de Uso'),
                    subtitle: const Text('Regras gerais da plataforma'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => AppRouter.router.push('/terms'),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.privacy_tip_outlined),
                    title: const Text('Política de Privacidade'),
                    subtitle: const Text('Como tratamos os seus dados'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => AppRouter.router.push('/privacy'),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.receipt_long_outlined),
                    title: const Text('Pagamentos e Reembolsos'),
                    subtitle: const Text(
                      'Cobranças, cancelamentos e devoluções',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => AppRouter.router.push('/refund-policy'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            child: ListTile(
              leading: const Icon(Icons.lock_reset),
              title: Text(t('sign_out_all')),
              onTap: _signOutAll,
            ),
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            color: AppColors.alertRed.withValues(alpha: 0.05),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t('danger_zone'),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.alertRed,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.delete_forever_outlined,
                      color: AppColors.alertRed,
                    ),
                    title: Text(t('delete_account')),
                    subtitle: Text(t('delete_account_desc')),
                    trailing: _requestingDeletion
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.chevron_right),
                    onTap: _requestingDeletion ? null : _requestAccountDeletion,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryRed,
              foregroundColor: AppColors.cleanWhite,
            ),
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Text(t('save')),
          ),
        ],
      ),
    );
    */
  }

  Widget _buildCompactRestaurantSettings() {
    String t(String key) => AppStrings.of(context, key);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Conta e segurança'),
        backgroundColor: AppColors.primaryRed,
        foregroundColor: AppColors.cleanWhite,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Segurança',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Card(
            elevation: 0,
            child: ListTile(
              leading: const Icon(Icons.lock_reset),
              title: Text(t('sign_out_all')),
              trailing: const Icon(Icons.chevron_right),
              onTap: _signOutAll,
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Conta',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Card(
            elevation: 0,
            color: AppColors.alertRed.withValues(alpha: 0.05),
            child: ListTile(
              leading: const Icon(
                Icons.delete_forever_outlined,
                color: AppColors.alertRed,
              ),
              title: Text(t('delete_account')),
              subtitle: Text(t('delete_account_desc')),
              trailing: _requestingDeletion
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chevron_right),
              onTap: _requestingDeletion ? null : _requestAccountDeletion,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(String email, String Function(String) t) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppColors.splashGradient,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 24,
            backgroundColor: Colors.white,
            child: Icon(Icons.person, color: AppColors.primaryRed),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t('your_account'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  email.isNotEmpty ? email : 'Atualize seus dados pessoais',
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
