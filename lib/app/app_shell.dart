import 'package:flutter/material.dart';

import '../services/app_language_controller.dart';
import 'app_providers.dart';
import 'bootstrap_failure_app.dart';
import 'deligo_app.dart';

class AppShell extends StatelessWidget {
  final AppLanguageController languageController;
  final String? fatalError;

  const AppShell({
    super.key,
    required this.languageController,
    this.fatalError,
  });

  bool get isReady => fatalError == null;

  @override
  Widget build(BuildContext context) {
    if (!isReady) {
      return BootstrapFailureApp(error: fatalError!);
    }

    return AppProviders(
      languageController: languageController,
      child: const DeligoApp(),
    );
  }
}
