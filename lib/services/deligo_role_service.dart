import 'package:supabase_flutter/supabase_flutter.dart';

class DeligoPlatformRole {
  const DeligoPlatformRole({required this.slug, required this.status});
  final String slug;
  final String status;

  bool get isActive => status == 'active';
}

class DeligoRoleService {
  DeligoRoleService._();
  static final instance = DeligoRoleService._();
  final _client = Supabase.instance.client;

  Future<List<DeligoPlatformRole>> getMyRoles() async {
    final raw = await _client.rpc('get_my_deligo_roles');
    if (raw is! List) {
      return const [];
    }
    return raw
        .whereType<Map>()
        .map(
          (item) => DeligoPlatformRole(
            slug: item['role_slug']?.toString() ?? '',
            status: item['status']?.toString() ?? 'pending',
          ),
        )
        .where((role) => role.slug.isNotEmpty)
        .toList();
  }

  Future<DeligoPlatformRole> activate(String roleSlug) async {
    final raw = await _client.rpc(
      'activate_my_deligo_role',
      params: {'p_role_slug': roleSlug},
    );
    final row = raw is List && raw.isNotEmpty && raw.first is Map
        ? raw.first as Map
        : null;
    if (row == null) {
      throw const AuthException('Não foi possível activar o perfil DeliGo.');
    }
    return DeligoPlatformRole(
      slug: row['role_slug']?.toString() ?? roleSlug,
      status: row['status']?.toString() ?? 'pending',
    );
  }
}
