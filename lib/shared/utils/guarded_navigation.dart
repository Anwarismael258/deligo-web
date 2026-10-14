import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Prevents a burst of taps from stacking identical GoRouter pages.
///
/// The guard is released when the pushed page is popped, so returning to a
/// list still allows the user to open the same item again normally.
class GuardedNavigation {
  GuardedNavigation._();

  static final Set<String> _active = <String>{};

  static Future<T?> push<T>(BuildContext context, String location) async {
    final key = '${identityHashCode(context)}::$location';
    debugPrint('[NAV] tentativa location=$location');
    debugPrint('[NAV] key=$key');
    debugPrint('[NAV] active antes=${_active.toList()}');
    final added = _active.add(key);
    debugPrint('[NAV] add result=$added');
    if (!added) {
      debugPrint('[NAV] bloqueado: key ja estava em _active');
      return null;
    }
    try {
      if (!context.mounted) return null;
      debugPrint('[NAV] push iniciado');
      return await context.push<T>(location);
    } finally {
      debugPrint('[NAV] push terminou');
      debugPrint('[NAV] removendo key=$key');
      _active.remove(key);
      debugPrint('[NAV] active depois=${_active.toList()}');
    }
  }
}
