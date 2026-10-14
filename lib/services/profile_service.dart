import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Servico para gerenciar upload de foto de perfil.
class ProfileService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final ImagePicker _picker = ImagePicker();

  /// Bucket para fotos de perfil.
  static const String _avatarBucket = 'avatars';

  /// Selecionar e fazer upload de foto de perfil.
  Future<String?> uploadProfilePhoto() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 500,
        maxHeight: 500,
        imageQuality: 85,
      );

      if (image == null) return null;
      return uploadAvatarBytes(await image.readAsBytes());
    } catch (e) {
      debugPrint('Erro ao selecionar imagem: $e');
      return null;
    }
  }

  /// Tirar foto com camera.
  Future<String?> takeProfilePhoto() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 500,
        maxHeight: 500,
        imageQuality: 85,
      );

      if (image == null) return null;
      return uploadAvatarBytes(await image.readAsBytes());
    } catch (e) {
      debugPrint('Erro ao tirar foto: $e');
      return null;
    }
  }

  /// Upload de avatar.
  Future<String?> uploadAvatarBytes(Uint8List bytes) async {
    try {
      var session = _supabase.auth.currentSession;
      if (session == null || session.isExpired) {
        final refreshed = await _supabase.auth.refreshSession();
        session = refreshed.session;
      }
      final user = session?.user ?? _supabase.auth.currentUser;
      if (user == null) {
        debugPrint('Usuario nao autenticado');
        return null;
      }

      await _ensureBucketExists(_avatarBucket);

      final fileName =
          'avatar_${user.id}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final path = '${user.id}/$fileName';

      await _supabase.storage
          .from(_avatarBucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              upsert: true,
              contentType: 'image/jpeg',
            ),
          );

      final publicUrl = _supabase.storage
          .from(_avatarBucket)
          .getPublicUrl(path);
      final updated = await updateProfileAvatar(
        '$publicUrl?v=${DateTime.now().millisecondsSinceEpoch}',
      );
      return updated
          ? '$publicUrl?v=${DateTime.now().millisecondsSinceEpoch}'
          : null;
    } catch (e) {
      debugPrint('Erro ao fazer upload do avatar: $e');
      return null;
    }
  }

  /// Garantir que o bucket existe.
  Future<void> _ensureBucketExists(String bucketName) async {
    try {
      await _supabase.storage.listBuckets();
    } catch (e) {
      debugPrint('Erro ao verificar buckets: $e');
    }
  }

  /// Atualizar avatar no perfil.
  Future<bool> updateProfileAvatar(String avatarUrl) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return false;

      await _supabase
          .from('profiles')
          .update({
            'avatar_url': avatarUrl,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', user.id);

      return true;
    } catch (e) {
      debugPrint('Erro ao atualizar avatar: $e');
      return false;
    }
  }

  /// Remover foto de perfil.
  Future<bool> removeProfilePhoto() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return false;

      await _supabase
          .from('profiles')
          .update({
            'avatar_url': null,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', user.id);

      return true;
    } catch (e) {
      debugPrint('Erro ao remover avatar: $e');
      return false;
    }
  }

  /// Buscar foto de perfil do usuario.
  Future<String?> getProfilePhoto() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return null;

      final response = await _supabase
          .from('profiles')
          .select('avatar_url')
          .eq('id', user.id)
          .maybeSingle();

      return response?['avatar_url'] as String?;
    } catch (e) {
      debugPrint('Erro ao buscar foto: $e');
      return null;
    }
  }

  /// Atualizar perfil completo.
  Future<bool> updateProfile({
    String? fullName,
    String? phone,
    String? avatarUrl,
  }) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return false;

      final updates = <String, dynamic>{
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (fullName != null) updates['full_name'] = fullName;
      if (phone != null) updates['phone'] = phone;
      if (avatarUrl != null) updates['avatar_url'] = avatarUrl;

      await _supabase.from('profiles').update(updates).eq('id', user.id);
      return true;
    } catch (e) {
      debugPrint('Erro ao atualizar perfil: $e');
      return false;
    }
  }
}
