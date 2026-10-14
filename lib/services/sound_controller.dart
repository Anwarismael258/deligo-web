import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'courier_offer_feedback_deadline.dart';

enum AppSoundType {
  click,
  shortBang,
  notification,
  success,
  error,
  messageSent,
  orderConfirmed,
  newOrderRestaurant,
  orderAccepted,
  preparing,
  driverAssigned,
  driverArriving,
  delivered,
  newOrderDriver,
  newDispute,
  reviewReceived,
  activityReminder,
  messageReceived,
}

class SoundController {
  SoundController._();

  static final SoundController instance = SoundController._();
  static const String _courierDispatchLoopAsset = 'sounds/platinum (1).mp3';

  final AudioPlayer _player = AudioPlayer();
  final AudioPlayer _dispatchPlayer = AudioPlayer();
  bool _enabled = true;
  bool _courierDispatchLoopActive = false;
  String? _courierDispatchOrderId;
  String? _courierDispatchAttemptId;
  Timer? _criticalAlertTimer;
  Completer<void>? _criticalAlertWaiter;
  int _criticalAlertGeneration = 0;
  String? _criticalAlertKey;
  final Map<String, DateTime> _restaurantOrderAlerts = <String, DateTime>{};
  bool get isEnabled => _enabled;
  bool get isCourierDispatchLoopActive => _courierDispatchLoopActive;
  String? get courierDispatchOrderId => _courierDispatchOrderId;
  String? get courierDispatchAttemptId => _courierDispatchAttemptId;

  void clearUserScopedAlertHistory() => _restaurantOrderAlerts.clear();

  Future<void> init() async {
    await _player.setReleaseMode(ReleaseMode.stop);
    await _dispatchPlayer.setReleaseMode(ReleaseMode.stop);
    await refreshFromProfile();
  }

  Future<void> refreshFromProfile() async {
    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) return;
      final profile = await client
          .from('profiles')
          .select('settings, sound_enabled')
          .eq('id', user.id)
          .maybeSingle();
      final settings =
          (profile?['settings'] as Map?)?.cast<String, dynamic>() ?? {};
      _enabled =
          (settings['sound_enabled'] as bool?) ??
          (profile?['sound_enabled'] as bool?) ??
          true;
    } catch (e) {
      debugPrint('SoundController.refreshFromProfile error: $e');
    }
  }

  Future<void> setEnabled(bool value, {bool persist = true}) async {
    _enabled = value;
    if (!value) {
      try {
        await _player.stop();
      } catch (_) {}
      await stopRestaurantOrderAlert();
      await stopCourierDispatchLoop();
    }
    if (!persist) return;
    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) return;
      final profile = await client
          .from('profiles')
          .select('settings')
          .eq('id', user.id)
          .maybeSingle();
      final settings =
          (profile?['settings'] as Map?)?.cast<String, dynamic>() ?? {};
      settings['sound_enabled'] = value;
      await client
          .from('profiles')
          .update({
            'settings': settings,
            'sound_enabled': value,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', user.id);
    } catch (e) {
      debugPrint('SoundController.setEnabled error: $e');
    }
  }

  Future<void> play(AppSoundType type) async {
    if (!_enabled) return;
    try {
      await _player.stop();
      await _player.play(
        AssetSource(_assetFor(type)),
        volume: _volumeFor(type),
      );
      await HapticFeedback.selectionClick();
    } catch (e) {
      debugPrint('SoundController.play error: $e');
      await _fallbackSystem(type);
    }
  }

  Future<void> click() => play(AppSoundType.click);
  Future<void> shortBang() => play(AppSoundType.shortBang);
  Future<void> notification() => play(AppSoundType.notification);
  Future<void> success() => play(AppSoundType.success);
  Future<void> error() => play(AppSoundType.error);
  Future<void> messageSent() => play(AppSoundType.messageSent);
  Future<void> orderConfirmed() => play(AppSoundType.orderConfirmed);
  Future<void> newOrderRestaurant() => play(AppSoundType.newOrderRestaurant);
  Future<void> orderAccepted() => play(AppSoundType.orderAccepted);
  Future<void> preparing() => play(AppSoundType.preparing);
  Future<void> driverAssigned() => play(AppSoundType.driverAssigned);
  Future<void> driverArriving() => play(AppSoundType.driverArriving);
  Future<void> delivered() => play(AppSoundType.delivered);
  Future<void> newOrderDriver() => play(AppSoundType.newOrderDriver);
  Future<void> newDispute() => play(AppSoundType.newDispute);
  Future<void> reviewReceived() => play(AppSoundType.reviewReceived);
  Future<void> activityReminder() => play(AppSoundType.activityReminder);
  Future<void> messageReceived() => play(AppSoundType.messageReceived);

  Future<void> startCourierDispatchLoop({
    String? orderId,
    String? attemptId,
    DateTime? expiresAt,
    Duration offerTimeout = const Duration(seconds: 25),
  }) async {
    if (!_enabled) return;
    final nextOrderId = orderId?.trim();
    final nextAttemptId = attemptId?.trim();
    if (_courierDispatchLoopActive &&
        _courierDispatchOrderId == nextOrderId &&
        _courierDispatchAttemptId == nextAttemptId) {
      return;
    }
    if (nextOrderId == null ||
        nextOrderId.isEmpty ||
        nextAttemptId == null ||
        nextAttemptId.isEmpty ||
        expiresAt == null) {
      return;
    }
    final now = DateTime.now();
    final effectiveDeadline = CourierOfferFeedbackDeadline.effective(
      now: now,
      individualTimeout: offerTimeout,
      offerExpiresAt: expiresAt,
    );
    if (effectiveDeadline == null) return;
    final generation = ++_criticalAlertGeneration;
    _cancelCriticalAlertWait();
    _courierDispatchLoopActive = true;
    _courierDispatchOrderId = nextOrderId;
    _courierDispatchAttemptId = nextAttemptId;
    _criticalAlertKey = 'courier:$nextOrderId:$nextAttemptId';
    try {
      await _dispatchPlayer.stop();
      if (generation != _criticalAlertGeneration) return;
      await _dispatchPlayer.setReleaseMode(ReleaseMode.loop);
      if (generation != _criticalAlertGeneration) return;
      await _dispatchPlayer.play(
        AssetSource(_courierDispatchLoopAsset),
        volume: 1.0,
      );
      await HapticFeedback.heavyImpact();
      final remaining = effectiveDeadline.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        await stopCourierDispatchLoop(orderId: nextOrderId);
      } else {
        _criticalAlertTimer = Timer(remaining, () {
          if (generation == _criticalAlertGeneration) {
            unawaited(stopCourierDispatchLoop(orderId: nextOrderId));
          }
        });
      }
    } catch (e) {
      if (generation == _criticalAlertGeneration) {
        _courierDispatchLoopActive = false;
        _courierDispatchOrderId = null;
        _courierDispatchAttemptId = null;
        _criticalAlertKey = null;
        debugPrint('SoundController.startCourierDispatchLoop error: $e');
        await _fallbackSystem(AppSoundType.newOrderDriver);
      }
    }
  }

  Future<void> stopCourierDispatchLoop({
    String? orderId,
    String? attemptId,
  }) async {
    if (!_courierDispatchLoopActive) return;
    final requestedOrderId = orderId?.trim();
    final activeOrderId = _courierDispatchOrderId?.trim();
    if (requestedOrderId != null &&
        requestedOrderId.isNotEmpty &&
        requestedOrderId != activeOrderId) {
      return;
    }
    final requestedAttemptId = attemptId?.trim();
    final activeAttemptId = _courierDispatchAttemptId?.trim();
    if (requestedAttemptId != null &&
        requestedAttemptId.isNotEmpty &&
        requestedAttemptId != activeAttemptId) {
      return;
    }
    _courierDispatchLoopActive = false;
    _courierDispatchOrderId = null;
    _courierDispatchAttemptId = null;
    _criticalAlertKey = null;
    final generation = ++_criticalAlertGeneration;
    _cancelCriticalAlertWait();
    try {
      await _dispatchPlayer.stop();
      if (generation != _criticalAlertGeneration) return;
      await _dispatchPlayer.setReleaseMode(ReleaseMode.stop);
    } catch (e) {
      debugPrint('SoundController.stopCourierDispatchLoop error: $e');
    }
  }

  Future<void> startRestaurantOrderAlert({
    String? orderId,
    int repeats = 4,
  }) async {
    if (!_enabled) return;
    final normalizedOrderId = orderId?.trim() ?? '';
    if (normalizedOrderId.isEmpty) return;
    final now = DateTime.now();
    _restaurantOrderAlerts.removeWhere(
      (_, seenAt) => now.difference(seenAt) > const Duration(minutes: 10),
    );
    final key = 'restaurant:$normalizedOrderId';
    if (_restaurantOrderAlerts.containsKey(key)) return;
    _restaurantOrderAlerts[key] = now;
    while (_restaurantOrderAlerts.length > 512) {
      _restaurantOrderAlerts.remove(_restaurantOrderAlerts.keys.first);
    }
    if (_criticalAlertKey == key) return;

    final generation = ++_criticalAlertGeneration;
    _cancelCriticalAlertWait();
    _courierDispatchLoopActive = false;
    _courierDispatchOrderId = null;
    _courierDispatchAttemptId = null;
    _criticalAlertKey = key;
    try {
      await _dispatchPlayer.stop();
      if (generation != _criticalAlertGeneration) return;
      await _dispatchPlayer.setReleaseMode(ReleaseMode.stop);
      for (var index = 0; index < repeats; index++) {
        if (generation != _criticalAlertGeneration) return;
        await _dispatchPlayer.play(
          AssetSource(_assetFor(AppSoundType.newOrderRestaurant)),
          volume: 1.0,
        );
        await HapticFeedback.heavyImpact();
        if (index + 1 < repeats &&
            !await _waitForCriticalAlert(
              const Duration(milliseconds: 1500),
              generation,
            )) {
          return;
        }
      }
      if (generation == _criticalAlertGeneration) _criticalAlertKey = null;
    } catch (error) {
      if (generation == _criticalAlertGeneration) {
        _criticalAlertKey = null;
        debugPrint('SoundController.startRestaurantOrderAlert error: $error');
        await _fallbackSystem(AppSoundType.newOrderRestaurant);
      }
    }
  }

  Future<void> stopRestaurantOrderAlert({String? orderId}) async {
    final requested = orderId?.trim() ?? '';
    final activeKey = _criticalAlertKey ?? '';
    if (!activeKey.startsWith('restaurant:')) return;
    if (requested.isNotEmpty && activeKey != 'restaurant:$requested') return;
    _criticalAlertGeneration++;
    final generation = _criticalAlertGeneration;
    _cancelCriticalAlertWait();
    _criticalAlertKey = null;
    try {
      await _dispatchPlayer.stop();
      if (generation != _criticalAlertGeneration) return;
      await _dispatchPlayer.setReleaseMode(ReleaseMode.stop);
    } catch (error) {
      debugPrint('SoundController.stopRestaurantOrderAlert error: $error');
    }
  }

  Future<bool> _waitForCriticalAlert(Duration duration, int generation) async {
    if (generation != _criticalAlertGeneration) return false;
    final waiter = Completer<void>();
    _criticalAlertWaiter = waiter;
    _criticalAlertTimer = Timer(duration, () {
      if (!waiter.isCompleted) waiter.complete();
    });
    await waiter.future;
    _criticalAlertTimer?.cancel();
    _criticalAlertTimer = null;
    if (identical(_criticalAlertWaiter, waiter)) _criticalAlertWaiter = null;
    return generation == _criticalAlertGeneration;
  }

  void _cancelCriticalAlertWait() {
    _criticalAlertTimer?.cancel();
    _criticalAlertTimer = null;
    final waiter = _criticalAlertWaiter;
    _criticalAlertWaiter = null;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
  }

  Future<void> orderAlertRing({int repeats = 4}) async {
    if (!_enabled) return;
    try {
      await _player.stop();
      await _player.setReleaseMode(ReleaseMode.stop);
      for (var index = 0; index < repeats; index++) {
        await _player.play(
          AssetSource(_assetFor(AppSoundType.newOrderRestaurant)),
          volume: 1.0,
        );
        await HapticFeedback.heavyImpact();
        await Future<void>.delayed(const Duration(milliseconds: 1500));
      }
    } catch (e) {
      debugPrint('SoundController.orderAlertRing error: $e');
      await _fallbackSystem(AppSoundType.newOrderRestaurant);
    }
  }

  Future<void> driverDispatchRing({int repeats = 3}) async {
    if (!_enabled) return;
    try {
      await _player.stop();
      await _player.setReleaseMode(ReleaseMode.stop);
      for (var index = 0; index < repeats; index++) {
        await _player.play(
          AssetSource(_assetFor(AppSoundType.newOrderDriver)),
          volume: 1.0,
        );
        await HapticFeedback.heavyImpact();
        await Future<void>.delayed(const Duration(milliseconds: 1200));
      }
    } catch (e) {
      debugPrint('SoundController.driverDispatchRing error: $e');
      await _fallbackSystem(AppSoundType.newOrderDriver);
    }
  }

  String _assetFor(AppSoundType type) {
    switch (type) {
      case AppSoundType.click:
        return 'sounds/click.wav';
      case AppSoundType.shortBang:
        return 'sounds/notification.wav';
      case AppSoundType.notification:
        return 'sounds/notification.wav';
      case AppSoundType.messageSent:
        return 'sounds/pop out.mp3';
      case AppSoundType.newOrderRestaurant:
        return _courierDispatchLoopAsset;
      case AppSoundType.success:
      case AppSoundType.orderAccepted:
      case AppSoundType.preparing:
      case AppSoundType.driverAssigned:
      case AppSoundType.reviewReceived:
      case AppSoundType.activityReminder:
        return 'sounds/notification.wav';
      case AppSoundType.driverArriving:
        return 'sounds/short-bang.mp3';
      case AppSoundType.messageReceived:
        return 'sounds/notification.wav';
      case AppSoundType.error:
        return 'sounds/error.mp3';
      case AppSoundType.orderConfirmed:
        return 'sounds/notification.wav';
      case AppSoundType.delivered:
        return 'sounds/notification.wav';
      case AppSoundType.newOrderDriver:
        return _courierDispatchLoopAsset;
      case AppSoundType.newDispute:
        return 'sounds/notification.wav';
    }
  }

  double _volumeFor(AppSoundType type) {
    switch (type) {
      case AppSoundType.click:
        return 0.55;
      case AppSoundType.shortBang:
        return 1;
      case AppSoundType.notification:
        return 0.9;
      case AppSoundType.success:
        return 0.75;
      case AppSoundType.messageSent:
        return 0.9;
      case AppSoundType.error:
        return 1;
      case AppSoundType.orderConfirmed:
      case AppSoundType.newOrderRestaurant:
      case AppSoundType.newDispute:
        return 0.9;
      case AppSoundType.orderAccepted:
      case AppSoundType.preparing:
      case AppSoundType.driverAssigned:
        return 0.9;
      case AppSoundType.driverArriving:
        return 1;
      case AppSoundType.reviewReceived:
        return 0.95;
      case AppSoundType.delivered:
        return 1;
      case AppSoundType.newOrderDriver:
        return 1;
      case AppSoundType.activityReminder:
        return 0.85;
      case AppSoundType.messageReceived:
        return 0.95;
    }
  }

  Future<void> _fallbackSystem(AppSoundType type) async {
    switch (type) {
      case AppSoundType.error:
        await SystemSound.play(SystemSoundType.alert);
        await HapticFeedback.heavyImpact();
        break;
      case AppSoundType.notification:
      case AppSoundType.shortBang:
      case AppSoundType.success:
      case AppSoundType.messageSent:
      case AppSoundType.orderConfirmed:
      case AppSoundType.newOrderRestaurant:
      case AppSoundType.orderAccepted:
      case AppSoundType.preparing:
      case AppSoundType.driverAssigned:
      case AppSoundType.driverArriving:
      case AppSoundType.delivered:
      case AppSoundType.newOrderDriver:
      case AppSoundType.newDispute:
      case AppSoundType.reviewReceived:
      case AppSoundType.activityReminder:
      case AppSoundType.messageReceived:
        await SystemSound.play(SystemSoundType.alert);
        await HapticFeedback.mediumImpact();
        break;
      case AppSoundType.click:
        await SystemSound.play(SystemSoundType.click);
        break;
    }
  }
}
