import 'dart:async';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app_shell.dart';
import 'config/app_env.dart';
import 'services/app_language_controller.dart';
import 'services/app_variant_service.dart';
import 'services/firebase_analytics_service.dart';
import 'services/push_notification_service.dart';
import 'services/sound_controller.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  await PushNotificationService.handleBackgroundMessage(message);
}

class _AppBootstrapResult {
  final AppLanguageController languageController;
  final String? fatalError;

  const _AppBootstrapResult({
    required this.languageController,
    this.fatalError,
  });

  bool get isReady => fatalError == null;
}

Future<_AppBootstrapResult> _bootstrapApp() async {
  final languageController = AppLanguageController();

  try {
    await _loadEnvironment();

    final supabaseUrl = AppEnv.supabaseUrl;
    final supabaseAnonKey = AppEnv.supabaseAnonKey;

    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
      throw StateError(
        'SUPABASE_URL and SUPABASE_ANON_KEY required. Configure via '
        '.env, assets/config/public.env or --dart-define.',
      );
    }

    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
    await AppVariantService.init();
    await languageController.init();

    return _AppBootstrapResult(languageController: languageController);
  } catch (e) {
    debugPrint('Bootstrap fatal error: $e');
    return _AppBootstrapResult(
      languageController: languageController,
      fatalError: e.toString(),
    );
  }
}

Future<_AppBootstrapResult> _bootstrapWebApp() async {
  final languageController = AppLanguageController();

  try {
    await _loadEnvironment();

    final supabaseUrl = AppEnv.supabaseUrl;
    final supabaseAnonKey = AppEnv.supabaseAnonKey;

    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
      throw StateError(
        'SUPABASE_URL and SUPABASE_ANON_KEY required. Configure via '
        '.env, assets/config/public.env or --dart-define.',
      );
    }

    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
    await AppVariantService.init();
    await languageController.init();

    return _AppBootstrapResult(languageController: languageController);
  } catch (e) {
    debugPrint('Web bootstrap fatal error: $e');
    return _AppBootstrapResult(
      languageController: languageController,
      fatalError: e.toString(),
    );
  }
}

Future<void> _loadEnvironment() async {
  try {
    await dotenv.load(fileName: '.env');
    return;
  } catch (e) {
    debugPrint(
      'Aviso: .env nao carregado, tentando assets/config/public.env: $e',
    );
  }

  try {
    await dotenv.load(fileName: 'assets/config/public.env');
  } catch (e) {
    debugPrint(
      'Aviso: assets/config/public.env nao carregado, usando dart-defines: $e',
    );
  }
}

void _startDeferredNativeServices() {
  if (kIsWeb) return;

  Future<void>.delayed(const Duration(milliseconds: 100), () async {
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(
        _firebaseMessagingBackgroundHandler,
      );
    } catch (e) {
      debugPrint('Aviso: Firebase nao inicializado: $e');
      return;
    }

    unawaited(FirebaseAnalyticsService.instance.initialize());

    try {
      await SoundController.instance.init();
    } catch (e) {
      debugPrint('Sound init error: $e');
    }

    Future<void> initializePushIfSignedIn() async {
      if (Supabase.instance.client.auth.currentUser == null) return;
      try {
        await PushNotificationService().initialize();
      } catch (e) {
        debugPrint('Push init error: $e');
      }
    }

    unawaited(initializePushIfSignedIn());
    Supabase.instance.client.auth.onAuthStateChange.listen((event) {
      if (event.session == null) return;
      unawaited(initializePushIfSignedIn());
    });
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('Flutter fatal error: ${details.exceptionAsString()}');
  };
  ErrorWidget.builder = (details) => Material(
    color: const Color(0xFFFFF5F5),
    child: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Não foi possível abrir esta tela agora.\nVolte e tente novamente.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFB42318),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    ),
  );
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Platform fatal error: $error');
    debugPrintStack(stackTrace: stack);
    return true;
  };

  final bootstrap = await (kIsWeb ? _bootstrapWebApp() : _bootstrapApp()).timeout(
    const Duration(seconds: 20),
    onTimeout: () => _AppBootstrapResult(
      languageController: AppLanguageController(),
      fatalError:
          'Tempo limite ao iniciar o app. Verifique a internet, Firebase e Supabase.',
    ),
  );

  runApp(
    AppShell(
      languageController: bootstrap.languageController,
      fatalError: bootstrap.fatalError,
    ),
  );

  if (bootstrap.isReady) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startDeferredNativeServices();
    });
  }
}
