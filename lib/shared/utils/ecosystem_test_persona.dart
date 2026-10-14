import 'package:supabase_flutter/supabase_flutter.dart';

/// Identifies the three internal ecosystem personas without persisting secrets.
class EcosystemTestPersona {
  static const phoneSuffixes = <String>{'841130015', '827688695', '877688695'};

  static bool matches(User? user) {
    if (user == null) return false;
    final candidates = <String?>[
      user.phone,
      user.email,
      user.userMetadata?['phone']?.toString(),
      user.userMetadata?['phone_number']?.toString(),
    ];
    return candidates.whereType<String>().any((value) {
      final digits = value.replaceAll(RegExp(r'\D'), '');
      return phoneSuffixes.any(digits.endsWith);
    });
  }
}
