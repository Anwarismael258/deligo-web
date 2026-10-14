import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';

class ImageService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final ImagePicker _picker = ImagePicker();

  /// Pick and upload image
  Future<String?> uploadImage(String bucket, String folder) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 80,
      );

      if (image == null) return null;

      return await uploadFileBytes(
        bucket,
        folder,
        await image.readAsBytes(),
        image.name,
      );
    } catch (e) {
      debugPrint('Erro ao selecionar imagem: $e');
      return null;
    }
  }

  Future<String?> uploadVideo(
    String bucket,
    String folder, {
    Duration maxDuration = const Duration(seconds: 10),
    int maxBytes = 30 * 1024 * 1024,
  }) async {
    try {
      final XFile? video = await _picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: maxDuration,
      );
      if (video == null) return null;

      final bytes = await video.readAsBytes();
      if (bytes.length > maxBytes) {
        debugPrint('Video maior que o limite permitido.');
        return null;
      }
      return await uploadFileBytes(bucket, folder, bytes, video.name);
    } catch (e) {
      debugPrint('Erro ao selecionar video: $e');
      return null;
    }
  }

  /// Pick from a specific source and upload image
  Future<String?> uploadImageFromSource(
    String bucket,
    String folder,
    ImageSource source,
  ) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 85,
      );

      if (image == null) return null;
      return await uploadFileBytes(
        bucket,
        folder,
        await image.readAsBytes(),
        image.name,
      );
    } catch (e) {
      debugPrint('Erro ao selecionar imagem: $e');
      return null;
    }
  }

  /// Upload file to Supabase Storage
  Future<String?> uploadFileBytes(
    String bucket,
    String folder,
    Uint8List bytes,
    String originalName,
  ) async {
    try {
      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${originalName.split('/').last.split('\\').last}';
      final path = '$folder/$fileName';

      await _supabase.storage.from(bucket).uploadBinary(path, bytes);

      final publicUrl = _supabase.storage.from(bucket).getPublicUrl(path);

      return publicUrl;
    } catch (e) {
      debugPrint('Erro ao fazer upload: $e');
      return null;
    }
  }

  /// Delete image from storage
  Future<bool> deleteImage(String bucket, String path) async {
    try {
      await _supabase.storage.from(bucket).remove([path]);
      return true;
    } catch (e) {
      debugPrint('Erro ao excluir imagem: $e');
      return false;
    }
  }
}







