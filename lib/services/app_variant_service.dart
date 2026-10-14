import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AppVariantService {
  AppVariantService._();

  static const MethodChannel _channel = MethodChannel('com.deligo.app/app_info');
  static const String _compileVariant = String.fromEnvironment(
    'DELIGO_APP_VARIANT',
    defaultValue: 'app',
  );

  static String _variant = _normalize(_compileVariant);
  static String? _packageName;

  static String get variant => _variant;
  static String? get packageName => _packageName;
  static bool get isApp => _variant == 'app';
  static bool get isField => _variant == 'field';
  static bool get isMarketing => _variant == 'marketing';
  static bool get isStaff => isField || isMarketing;

  static Future<void> init() async {
    if (kIsWeb) {
      _variant = _normalize(_compileVariant);
      return;
    }

    try {
      final packageName = await _channel.invokeMethod<String>('packageName');
      _packageName = packageName?.trim();
      _variant = _variantFromPackage(_packageName) ?? _normalize(_compileVariant);
    } catch (error) {
      debugPrint('AppVariantService package lookup failed: $error');
      _variant = _normalize(_compileVariant);
    }
  }

  static String _normalize(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'field') return 'field';
    if (normalized == 'marketing' || normalized == 'publicidade') {
      return 'marketing';
    }
    return 'app';
  }

  static String? _variantFromPackage(String? packageName) {
    final normalized = packageName?.trim().toLowerCase() ?? '';
    if (normalized == 'deligo.field') return 'field';
    if (normalized == 'deligo.marketing' ||
        normalized == 'deligo.publicidade' ||
        normalized == 'deligo.marketing.publicidade') {
      return 'marketing';
    }
    if (normalized == 'com.deligo.app') return 'app';
    return null;
  }
}
