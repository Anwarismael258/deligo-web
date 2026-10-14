import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'features/onboarding/onboarding_page.dart';
import 'services/app_language_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final languageController = AppLanguageController();
  await languageController.init();

  final router = GoRouter(
    initialLocation: '/onboarding',
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingPage(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const _PreviewLoginPage(),
      ),
    ],
  );

  runApp(
    ChangeNotifierProvider.value(
      value: languageController,
      child: MaterialApp.router(
        title: 'DeliGo Onboarding Preview',
        routerConfig: router,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFE91C25)),
          useMaterial3: true,
        ),
      ),
    ),
  );
}

class _PreviewLoginPage extends StatelessWidget {
  const _PreviewLoginPage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFFFFF7F4),
      body: Center(
        child: Text(
          'Login DeliGo',
          style: TextStyle(
            color: Color(0xFF171717),
            fontSize: 32,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}
