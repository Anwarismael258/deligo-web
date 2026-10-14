import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'elevenlabs_audio_service.dart';

enum AppVoiceMode { full, importantOnly, off }

class WelcomeVoiceService {
  WelcomeVoiceService._();

  static final WelcomeVoiceService instance = WelcomeVoiceService._();
  static const _heardPrefix = 'welcome_voice_first_played_v2_';
  static const _dailyPrefix = 'welcome_voice_daily_v2_';

  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;
  final Set<String> _inFlightUsers = <String>{};

  Future<void> greetOnce({
    required String userId,
    required String name,
    required String role,
    String? gender,
    String? languageCode,
    String? voiceMode,
  }) async {
    final trimmedName = name.trim();
    if (userId.isEmpty || trimmedName.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    if (_inFlightUsers.contains(userId) || _isPlaying) return;

    final normalizedRole = role.trim().toLowerCase();
    final mode = _parseVoiceMode(voiceMode);
    if (mode == AppVoiceMode.off) return;

    final firstPlayKey = '$_heardPrefix$userId';
    final dailyKey = '$_dailyPrefix$userId';
    final now = DateTime.now();
    final todayKey = '${now.year}-${now.month}-${now.day}';
    final isFirstWelcome = prefs.getBool(firstPlayKey) != true;

    if (!isFirstWelcome) {
      if (mode != AppVoiceMode.full) return;
      if (prefs.getString(dailyKey) == todayKey) return;
    }

    _inFlightUsers.add(userId);
    try {
      final message = _buildMessage(
        name: trimmedName,
        role: normalizedRole,
        isFirstWelcome: isFirstWelcome,
        gender: gender,
        languageCode: languageCode,
      );

      final audioBytes = await ElevenLabsAudioService.instance.synthesize(
        text: message,
        languageCode: languageCode ?? 'pt',
      );
      if (audioBytes == null || audioBytes.isEmpty) return;

      _isPlaying = true;
      await _player.stop();
      await _player.play(BytesSource(audioBytes));
      if (isFirstWelcome) {
        await prefs.setBool(firstPlayKey, true);
      } else {
        await prefs.setString(dailyKey, todayKey);
      }
    } catch (e) {
      debugPrint('WelcomeVoiceService.greetOnce error: $e');
    } finally {
      _isPlaying = false;
      _inFlightUsers.remove(userId);
    }
  }

  String _buildMessage({
    required String name,
    required String role,
    required bool isFirstWelcome,
    String? gender,
    String? languageCode,
  }) {
    final normalizedLanguage = (languageCode ?? 'pt').toLowerCase();
    final normalizedGender = (gender ?? '').trim().toLowerCase();
    final shortName = _friendlyName(name);
    final hour = DateTime.now().hour;

    if (normalizedLanguage == 'en') {
      return _buildEnglishMessage(
        shortName: shortName,
        role: role,
        isFirstWelcome: isFirstWelcome,
        hour: hour,
      );
    }

    return _buildPortugueseMessage(
      shortName: shortName,
      role: role,
      isFirstWelcome: isFirstWelcome,
      hour: hour,
      gender: normalizedGender,
    );
  }

  AppVoiceMode _parseVoiceMode(String? value) {
    switch ((value ?? '').trim().toLowerCase()) {
      case 'full':
        return AppVoiceMode.full;
      case 'off':
        return AppVoiceMode.off;
      case 'important_only':
      default:
        return AppVoiceMode.importantOnly;
    }
  }

  String _friendlyName(String name) {
    final firstToken = name.trim().split(RegExp(r'\s+')).first;
    final cleaned = firstToken.replaceAll(RegExp(r"[^A-Za-z'-]"), '');
    return cleaned.isEmpty ? 'amigo' : cleaned;
  }

  String _buildPortugueseMessage({
    required String shortName,
    required String role,
    required bool isFirstWelcome,
    required int hour,
    required String gender,
  }) {
    final feminine = gender == 'feminino' || gender == 'female';
    if (isFirstWelcome) {
      switch (role) {
        case 'courier':
          return 'Bem-vindo ao DeliGo. Está disponível para receber entregas. Conduza com segurança.';
        case 'restaurant':
          return 'Bem-vindo ao Deligo! O seu restaurante ja pode comecar a receber pedidos. Vamos fazer um grande dia de vendas.';
        case 'client':
        default:
          return feminine
              ? '$shortName, bem-vinda ao Deligo! A sua proxima refeicao esta a poucos toques.'
              : '$shortName, bem-vindo ao Deligo! A sua proxima refeicao esta a poucos toques.';
      }
    }

    switch (role) {
      case 'courier':
        if (hour >= 11 && hour < 14) {
          return 'Bem-vindo de volta, $shortName. Esta e uma boa hora para ganhar mais com entregas.';
        }
        if (hour >= 18 && hour < 22) {
          return '$shortName, a cidade esta ativa agora. Ha boas oportunidades de entrega a sua espera.';
        }
        return 'Bem-vindo de volta, $shortName. Pronto para ganhar hoje?';
      case 'restaurant':
        if (hour >= 11 && hour < 14) {
          return 'Bem-vindo de volta! A hora do almoco esta a comecar e novos pedidos podem chegar a qualquer momento.';
        }
        if (hour >= 18 && hour < 22) {
          return 'Bem-vindo de volta! Esta numa boa janela de jantar para vender mais hoje.';
        }
        return 'Bem-vindo de volta! O seu restaurante esta visivel para clientes agora.';
      case 'client':
      default:
        if (hour >= 6 && hour < 11) {
          return 'De volta ao Deligo, $shortName. O pequeno-almoco esta a poucos toques.';
        }
        if (hour >= 11 && hour < 15) {
          return '$shortName, esta na hora do almoco. Pronto para o seu proximo pedido?';
        }
        if (hour >= 18 && hour < 22) {
          return '$shortName, o jantar esta a poucos toques. Temos algo especial para si hoje.';
        }
        return 'Bem-vindo de volta ao Deligo, $shortName. Pronto para o seu proximo pedido?';
    }
  }

  String _buildEnglishMessage({
    required String shortName,
    required String role,
    required bool isFirstWelcome,
    required int hour,
  }) {
    if (isFirstWelcome) {
      switch (role) {
        case 'courier':
          return 'Welcome to Deligo, $shortName! Start earning today. Go online to receive your first order.';
        case 'restaurant':
          return 'Welcome to Deligo! Your restaurant is ready to receive orders. Let us make it a great sales day.';
        case 'client':
        default:
          return 'Welcome to Deligo, $shortName! Your next meal is just a few taps away.';
      }
    }

    switch (role) {
      case 'courier':
        if (hour >= 11 && hour < 14) {
          return 'Welcome back, $shortName. This is a strong time to earn with deliveries.';
        }
        if (hour >= 18 && hour < 22) {
          return '$shortName, it is a busy time right now. Orders are waiting for you.';
        }
        return 'Welcome back, $shortName. Ready to earn?';
      case 'restaurant':
        if (hour >= 11 && hour < 14) {
          return 'Welcome back! Lunch time is starting and new orders can come in anytime.';
        }
        if (hour >= 18 && hour < 22) {
          return 'Welcome back! Dinner time is a strong window to sell more today.';
        }
        return 'Welcome back! You are live and customers can see your restaurant now.';
      case 'client':
      default:
        if (hour >= 6 && hour < 11) {
          return 'Welcome back to Deligo, $shortName. Breakfast is just a few taps away.';
        }
        if (hour >= 11 && hour < 15) {
          return '$shortName, it is lunch time. Ready for your next order?';
        }
        if (hour >= 18 && hour < 22) {
          return '$shortName, dinner is just a few taps away. We have something special for you today.';
        }
        return 'Welcome back to Deligo, $shortName. Ready for your next order?';
    }
  }
}
