import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart' as legacy_provider;
import 'package:app_links/app_links.dart';
import 'dart:async';

import '../config/router/app_router.dart';
import '../config/theme/app_theme.dart';
import '../services/app_language_controller.dart';
import '../services/app_strings.dart';

class DeligoApp extends StatefulWidget {
  const DeligoApp({super.key});

  @override
  State<DeligoApp> createState() => _DeligoAppState();
}

class _DeligoAppState extends State<DeligoApp> {
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    _consumeInitialLink();
    _linkSubscription = _appLinks.uriLinkStream.listen(_handleLink);
  }

  Future<void> _consumeInitialLink() async {
    try {
      final uri = await _appLinks.getInitialLink();
      if (uri != null) _handleLink(uri);
    } catch (_) {
      // A malformed or unavailable external link must not block app startup.
    }
  }

  void _handleLink(Uri uri) {
    if (uri.scheme == 'deligo' && uri.host == 'invite') {
      final token = uri.queryParameters['share_token'];
      if (token != null && token.isNotEmpty) {
        AppRouter.router.go('/invite/${Uri.encodeComponent(token)}');
      }
      return;
    }

    // Universal/App Links may arrive as HTTPS when the app is installed.
    // Keep the same route as the browser landing page.
    if ((uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.pathSegments.length >= 2 &&
        uri.pathSegments.first == 'invite') {
      AppRouter.router.go(uri.path + (uri.hasQuery ? '?${uri.query}' : ''));
      return;
    }

    if (uri.scheme != 'deligo' || uri.host != 'wallet') return;
    final section = uri.queryParameters['section'] ?? 'deposit';
    final depositId = uri.queryParameters['deposit_id'];
    final query = <String, String>{'section': section};
    if (depositId != null && depositId.isNotEmpty) {
      query['deposit_id'] = depositId;
    }
    AppRouter.router.go(
      Uri(path: '/wallet', queryParameters: query).toString(),
    );
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final language = legacy_provider.Provider.of<AppLanguageController>(
      context,
    );
    return MaterialApp.router(
      title: AppStrings.of(context, 'app_title'),
      routerConfig: AppRouter.router,
      theme: kIsWeb ? AppTheme.webTheme : AppTheme.lightTheme,
      locale: language.locale,
      supportedLocales: const [Locale('pt'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      debugShowCheckedModeBanner: false,
    );
  }
}
