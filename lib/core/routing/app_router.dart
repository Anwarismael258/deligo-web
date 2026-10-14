import 'package:go_router/go_router.dart';

import '../../config/router/app_router.dart';

// Legacy compatibility export to avoid route drift.
GoRouter get appRouter => AppRouter.router;
