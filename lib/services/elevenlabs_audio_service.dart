import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ElevenLabsAudioService {
  ElevenLabsAudioService._();

  static final ElevenLabsAudioService instance = ElevenLabsAudioService._();

  Future<Uint8List?> synthesize({
    required String text,
    required String languageCode,
  }) async {
    final trimmedText = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (trimmedText.isEmpty) return null;

    try {
      final response = await Supabase.instance.client.functions.invoke(
        'elevenlabs-tts',
        body: {
          'text': trimmedText,
          'language': languageCode.trim().isEmpty ? 'pt' : languageCode,
        },
      ).timeout(const Duration(seconds: 25));

      final data = response.data;
      if (data is! Map) return null;
      final encoded = data['audio_base64']?.toString();
      if (encoded == null || encoded.isEmpty) return null;
      return base64Decode(encoded);
    } catch (error) {
      debugPrint('ElevenLabsAudioService.synthesize error: $error');
      return null;
    }
  }
}
