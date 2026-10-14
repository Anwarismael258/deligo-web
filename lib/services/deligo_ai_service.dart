import 'package:supabase_flutter/supabase_flutter.dart';

class DeligoAiService {
  DeligoAiService._();
  static final instance = DeligoAiService._();

  final SupabaseClient _client = Supabase.instance.client;

  Future<String> ask({required String message, String? tool}) async {
    final response = await _client.functions.invoke(
      'platform-ai',
      body: {
        'app_code': 'deligo',
        'task': tool ?? 'assistant',
        'prompt': message,
        'locale': 'pt-MZ',
      },
    );
    final data = response.data is Map
        ? Map<String, dynamic>.from(response.data as Map)
        : <String, dynamic>{};
    if (data['ok'] == true && data['answer'] is String) {
      return data['answer'] as String;
    }
    throw StateError(
      data['message']?.toString() ??
          data['error']?.toString() ??
          'DeliGo AI indisponível.',
    );
  }
}
