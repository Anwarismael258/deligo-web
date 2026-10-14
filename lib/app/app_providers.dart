import 'package:flutter/material.dart';
import 'package:provider/provider.dart' as legacy_provider;

import '../services/app_language_controller.dart';
import '../services/cart_service.dart';

class AppProviders extends StatelessWidget {
  final AppLanguageController languageController;
  final Widget child;

  const AppProviders({
    super.key,
    required this.languageController,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return legacy_provider.MultiProvider(
      providers: [
        legacy_provider.ChangeNotifierProvider(create: (_) => CartService()),
        legacy_provider.ChangeNotifierProvider.value(value: languageController),
      ],
      child: child,
    );
  }
}
