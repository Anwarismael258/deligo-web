import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_env.dart';

class KycService {
  KycService(this._supabase);

  final SupabaseClient _supabase;
  static const Duration _requestTimeout = Duration(seconds: 30);

  static const Map<String, List<String>> requiredLabelsByRole = {
    'restaurant': [
      'foto_loja',
      'foto_nuit',
      'foto_interior',
      'bi_frente',
      'bi_tras',
      'selfie',
    ],
    'courier': [
      'foto',
      'bi_frente',
      'bi_tras',
      'foto_veiculo',
      'foto_matricula',
      'carta_conducao',
      'documento_veiculo',
      'selfie_veiculo',
    ],
  };

  static List<String> requiredLabelsForRole(String role) {
    return List<String>.from(requiredLabelsByRole[role] ?? const []);
  }

  static Map<String, dynamic> parseJsonResponse(String body) => _parseJson(body);

  static Future<String?> validateImage(XFile file, String label) async {
    try {
      final length = await file.length();
      if (length <= 0) {
        return 'O documento $label esta vazio.';
      }
      if (length > 10 * 1024 * 1024) {
        return 'O documento $label excede 10MB.';
      }

      final mimeType = _contentTypeForPath(file.path);
      if (mimeType != 'image/jpeg' && mimeType != 'image/png') {
        return 'Formato invalido. Use JPG ou PNG para $label.';
      }
      return null;
    } catch (e) {
      return 'Nao foi possivel validar $label: $e';
    }
  }

  Future<Map<String, dynamic>> uploadAndSubmitKyc({
    required String subjectType,
    required String subjectName,
    required Map<String, XFile> files,
    Map<String, dynamic>? metadata,
  }) async {
    final session = _supabase.auth.currentSession;
    final user = _supabase.auth.currentUser;
    if (session == null || user == null) {
      throw Exception('Usuario nao autenticado');
    }

    final requiredLabels = requiredLabelsForRole(subjectType);
    if (requiredLabels.isEmpty) {
      throw Exception('Role KYC nao suportado: $subjectType');
    }

    for (final label in requiredLabels) {
      final file = files[label];
      if (file == null) {
        throw Exception('Documento obrigatorio em falta: $label');
      }
      final validationError = await validateImage(file, label);
      if (validationError != null) {
        throw Exception(validationError);
      }
    }

    final uploadRequestBody = {
      'subject_type': subjectType,
      'files': requiredLabels
          .map(
            (label) => {
              'label': label,
              'content_type': _contentTypeForPath(files[label]!.path),
            },
          )
          .toList(),
    };

    final uploadUrlsResponse = await _invokeFunctionDirect(
      'kyc-upload-urls',
      body: uploadRequestBody,
    ).timeout(_requestTimeout);

    final uploadUrlsJson = uploadUrlsResponse.json;
    if (uploadUrlsResponse.status >= 400) {
      throw Exception(
        uploadUrlsJson['error'] ??
            'Falha ao gerar URLs de upload (${uploadUrlsResponse.status})',
      );
    }

    final remoteFiles = (uploadUrlsJson['files'] as List? ?? const [])
        .cast<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    if (remoteFiles.length != requiredLabels.length) {
      throw Exception('O backend nao devolveu todas as URLs de upload KYC.');
    }

    final submittedDocuments = <String, Map<String, String>>{};
    for (final remoteFile in remoteFiles) {
      final label = remoteFile['label']?.toString() ?? '';
      final uploadUrl = _resolveUploadUrl(
          _supabase.storage.url,
          remoteFile['upload_url']?.toString() ?? '',
        );
      final path = remoteFile['path']?.toString() ?? '';
      final bucket = remoteFile['bucket']?.toString() ?? 'kyc';
      final contentType = _contentTypeForPath(files[label]!.path);
      final file = files[label];

      if (label.isEmpty || uploadUrl.isEmpty || path.isEmpty || file == null) {
        throw Exception('Resposta de upload KYC incompleta para $label.');
      }

      final bytes = await file.readAsBytes();
      final uploadResponse = await http.put(
        Uri.parse(uploadUrl),
        headers: {'Content-Type': _contentTypeForPath(file.path)},
        body: bytes,
      ).timeout(_requestTimeout);

      if (uploadResponse.statusCode < 200 || uploadResponse.statusCode >= 300) {
        throw Exception(
          'Falha ao enviar $label (${uploadResponse.statusCode}): ${uploadResponse.body}',
        );
      }

      submittedDocuments[label] = {
        'bucket': bucket,
        'path': path,
        'content_type': contentType,
      };
    }

    final submitBody = {
      'subject_type': subjectType,
      'subject_name': subjectName,
      'user_id': user.id,
      'documents': submittedDocuments,
      'metadata': {
        'submitted_from': 'mobile-app',
        'app_role': subjectType,
        ...?metadata,
      },
    };

    final submitResponse = await _invokeFunctionDirect(
      'submit_kyc',
      body: submitBody,
    ).timeout(_requestTimeout);

    final submitJson = submitResponse.json;
    if (submitResponse.status >= 400) {
      throw Exception(
        submitJson['error'] ??
            'Falha ao submeter KYC (${submitResponse.status})',
      );
    }

    return submitJson;
  }

  static String _contentTypeForPath(String path) {
    final normalized = path.toLowerCase();
    if (normalized.endsWith('.jpg') || normalized.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (normalized.endsWith('.png')) return 'image/png';
    return 'application/octet-stream';
  }

  static Map<String, dynamic> _parseJson(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
      return {'data': decoded};
    } catch (_) {
      return {'error': body};
    }
  }

  Future<_FunctionHttpResponse> _invokeFunctionDirect(
    String functionName, {
    required Map<String, dynamic> body,
  }) async {
    final token = (_supabase.auth.currentSession?.accessToken ?? '').trim();
    if (token.isEmpty) {
      throw Exception('Sessao expirada. Entre novamente e tente outra vez.');
    }

    final supabaseUrl = AppEnv.supabaseUrl.trim();
    final anonKey = AppEnv.supabaseAnonKey.trim();
    if (supabaseUrl.isEmpty || anonKey.isEmpty) {
      throw Exception('Configuracao do Supabase incompleta no app.');
    }

    final response = await http.post(
      Uri.parse('$supabaseUrl/functions/v1/$functionName'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
        'apikey': anonKey,
      },
      body: jsonEncode(body),
    );

    final json = _parseJson(response.body);
    return _FunctionHttpResponse(status: response.statusCode, json: json);
  }

  static String _resolveUploadUrl(String supabaseUrl, String uploadUrl) {
    final raw = uploadUrl.trim();
    if (raw.isEmpty) return raw;
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return raw;
    }
    if (raw.startsWith('/storage/')) {
      return '$supabaseUrl$raw';
    }
    if (raw.startsWith('/object/')) {
      return '$supabaseUrl/storage/v1$raw';
    }
    if (raw.startsWith('/')) {
      return '$supabaseUrl$raw';
    }
    return raw;
  }
}

class _FunctionHttpResponse {
  const _FunctionHttpResponse({
    required this.status,
    required this.json,
  });

  final int status;
  final Map<String, dynamic> json;
}
