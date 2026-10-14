import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

class FirebaseAnalyticsService {
  FirebaseAnalyticsService._();

  static final FirebaseAnalyticsService instance =
      FirebaseAnalyticsService._();

  FirebaseAnalytics? _analytics;
  FirebaseCrashlytics? _crashlytics;
  bool _initialized = false;

  NavigatorObserver? get observer =>
      _analytics == null ? null : FirebaseAnalyticsObserver(analytics: _analytics!);

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      _analytics = FirebaseAnalytics.instance;
      if (kReleaseMode) {
        _crashlytics = FirebaseCrashlytics.instance;
        await _crashlytics?.setCrashlyticsCollectionEnabled(true);
        FlutterError.onError = (details) {
          FlutterError.presentError(details);
          _crashlytics?.recordFlutterFatalError(details);
        };
      } else {
        // BlueStacks has a tight heap. Replaying large native crash reports in
        // a debug build can exhaust it before Flutter draws the first route.
        // Release APKs still collect Crashlytics reports normally.
        await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(false);
      }
      await _analytics?.logAppOpen();
      _initialized = true;
    } catch (e) {
      debugPrint('FirebaseAnalyticsService.initialize error: $e');
    }
  }

  Future<void> setUser({
    required String userId,
    String? role,
  }) async {
    try {
      await _analytics?.setUserId(id: userId);
      if (role != null && role.trim().isNotEmpty) {
        await _analytics?.setUserProperty(name: 'role', value: role.trim());
      }
      await _crashlytics?.setUserIdentifier(userId);
    } catch (e) {
      debugPrint('FirebaseAnalyticsService.setUser error: $e');
    }
  }

  Future<void> logEvent(
    String name, {
    Map<String, Object>? parameters,
  }) async {
    try {
      await _analytics?.logEvent(name: name, parameters: parameters);
    } catch (e) {
      debugPrint('FirebaseAnalyticsService.logEvent error: $e');
    }
  }

  Future<void> logPromoOpen({
    required String campaignId,
    String? restaurantId,
    String? source,
  }) async {
    await logEvent(
      'promo_open',
      parameters: {
        'campaign_id': campaignId,
        if (restaurantId != null && restaurantId.isNotEmpty)
          'restaurant_id': restaurantId,
        if (source != null && source.isNotEmpty) 'source': source,
      },
    );
  }

  Future<void> logNotificationOpen({
    required String type,
    String? entityId,
    String? action,
  }) async {
    await logEvent(
      'notification_open',
      parameters: {
        'type': type,
        if (entityId != null && entityId.isNotEmpty) 'entity_id': entityId,
        if (action != null && action.isNotEmpty) 'action': action,
      },
    );
  }

  Future<void> logCampaignDelivery({
    required String type,
    String? campaignId,
    String? restaurantId,
  }) async {
    await logEvent(
      'campaign_delivery',
      parameters: {
        'type': type,
        if (campaignId != null && campaignId.isNotEmpty)
          'campaign_id': campaignId,
        if (restaurantId != null && restaurantId.isNotEmpty)
          'restaurant_id': restaurantId,
      },
    );
  }
}
