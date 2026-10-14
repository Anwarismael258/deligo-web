import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AppLanguageController extends ChangeNotifier {
  AppLanguageController();

  static const String storageKey = 'deligo_language';
  String _languageCode = 'pt';

  String get languageCode => _languageCode;
  Locale get locale => Locale(_languageCode);
  bool get isEnglish => _languageCode == 'en';

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final localValue = prefs.getString(storageKey);
    if (localValue == 'pt' || localValue == 'en') {
      _languageCode = localValue!;
    } else {
      _languageCode = PlatformDispatcher.instance.locale.languageCode == 'en'
          ? 'en'
          : 'pt';
    }

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        final profile = await Supabase.instance.client
            .from('profiles')
            .select('settings')
            .eq('id', user.id)
            .maybeSingle();
        final settings =
            (profile?['settings'] as Map?)?.cast<String, dynamic>() ?? {};
        final profileLanguage = settings['language']?.toString();
        if (profileLanguage == 'pt' || profileLanguage == 'en') {
          _languageCode = profileLanguage!;
          await prefs.setString(storageKey, _languageCode);
        }
      }
    } catch (error) {
      debugPrint('AppLanguageController.init error: $error');
    }
  }

  Future<void> setLanguage(
    String languageCode, {
    bool persistRemote = false,
  }) async {
    if (languageCode != 'pt' && languageCode != 'en') return;
    if (_languageCode == languageCode && !persistRemote) return;

    _languageCode = languageCode;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(storageKey, languageCode);

    if (!persistRemote) return;
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('settings')
          .eq('id', user.id)
          .maybeSingle();
      final settings =
          (profile?['settings'] as Map?)?.cast<String, dynamic>() ?? {};
      settings['language'] = languageCode;
      await Supabase.instance.client
          .from('profiles')
          .update({
            'settings': settings,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', user.id);
    } catch (error) {
      debugPrint('AppLanguageController.setLanguage error: $error');
    }
  }
}
