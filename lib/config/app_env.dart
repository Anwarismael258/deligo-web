import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppEnv {
  static String _dotenvValue(String key) {
    try {
      return dotenv.env[key]?.trim() ?? '';
    } catch (_) {
      return '';
    }
  }

  static String _value(String key, String fallback) {
    if (fallback.trim().isNotEmpty) {
      return fallback.trim();
    }
    final dotenvValue = _dotenvValue(key);
    if (dotenvValue.isNotEmpty) {
      return dotenvValue;
    }
    return '';
  }

  static String get supabaseUrl =>
      _value('SUPABASE_URL', const String.fromEnvironment('SUPABASE_URL'));

  static String get supabaseAnonKey => _value(
    'SUPABASE_ANON_KEY',
    const String.fromEnvironment('SUPABASE_ANON_KEY'),
  );

  static String get googleMapsApiKey => _value(
    'GOOGLE_MAPS_API_KEY',
    const String.fromEnvironment('GOOGLE_MAPS_API_KEY'),
  );

  static String get mapboxAccessToken => _value(
    'MAPBOX_ACCESS_TOKEN',
    const String.fromEnvironment('MAPBOX_ACCESS_TOKEN'),
  );

  static String get firebaseWebApiKey => _value(
    'FIREBASE_WEB_API_KEY',
    const String.fromEnvironment('FIREBASE_WEB_API_KEY'),
  );

  static String get elevenLabsApiKey => _value(
    'ELEVENLABS_API_KEY',
    const String.fromEnvironment('ELEVENLABS_API_KEY'),
  );

  static String get elevenLabsVoiceId => _value(
    'ELEVENLABS_VOICE_ID',
    const String.fromEnvironment('ELEVENLABS_VOICE_ID'),
  );

  static String get elevenLabsVoiceIdEn => _value(
    'ELEVENLABS_VOICE_ID_EN',
    const String.fromEnvironment('ELEVENLABS_VOICE_ID_EN'),
  );

  static String get elevenLabsVoiceIdPt => _value(
    'ELEVENLABS_VOICE_ID_PT',
    const String.fromEnvironment('ELEVENLABS_VOICE_ID_PT'),
  );

  static String get deliveryFeeDefault => _value(
    'DELIVERY_FEE_DEFAULT',
    const String.fromEnvironment('DELIVERY_FEE_DEFAULT'),
  );

  static String get deligoShareBaseUrl => _value(
    'DELIGO_SHARE_BASE_URL',
    const String.fromEnvironment('DELIGO_SHARE_BASE_URL'),
  );

  static String get appShareBaseUrl => _value(
    'APP_SHARE_BASE_URL',
    const String.fromEnvironment('APP_SHARE_BASE_URL'),
  );

  static String get openWeatherApiKey => _value(
    'OPENWEATHER_API_KEY',
    const String.fromEnvironment('OPENWEATHER_API_KEY'),
  );
}
