import 'dart:async';

import 'notification_event.dart';
import 'sound_controller.dart';

class CriticalAlertController {
  CriticalAlertController._();
  static final CriticalAlertController instance = CriticalAlertController._();

  Future<void> start(NotificationEvent event) async {
    switch (event.sound) {
      case NotificationSound.courierOffer:
        await SoundController.instance.startCourierDispatchLoop(
          orderId: event.entityId,
          attemptId: event.attemptId,
          expiresAt: event.offerExpiresAt ?? event.dispatchExpiresAt,
        );
        return;
      case NotificationSound.restaurantOrder:
        await SoundController.instance.startRestaurantOrderAlert(
          orderId: event.entityId,
        );
        return;
      case NotificationSound.urgent:
        await SoundController.instance.play(AppSoundType.newOrderRestaurant);
        return;
      case NotificationSound.success:
        await SoundController.instance.success();
        return;
      case NotificationSound.error:
        await SoundController.instance.error();
        return;
      case NotificationSound.message:
        await SoundController.instance.messageReceived();
        return;
      case NotificationSound.notification:
        await SoundController.instance.notification();
        return;
      case NotificationSound.none:
        return;
    }
  }

  Future<void> stopFor(NotificationEvent event) async {
    if (event.isCourierOffer) {
      await SoundController.instance.stopCourierDispatchLoop(
        orderId: event.entityId,
        attemptId: event.attemptId,
      );
    }
    if (event.sound == NotificationSound.restaurantOrder) {
      await SoundController.instance.stopRestaurantOrderAlert(
        orderId: event.entityId,
      );
    }
  }

  Future<void> stopAll() async {
    await Future.wait([
      SoundController.instance.stopCourierDispatchLoop(),
      SoundController.instance.stopRestaurantOrderAlert(),
    ]);
  }
}
