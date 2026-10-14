import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class CourierForegroundService {
  CourierForegroundService._();

  static final CourierForegroundService instance = CourierForegroundService._();

  static const MethodChannel _channel = MethodChannel(
    'com.deligo.app/courier_foreground_service',
  );

  bool get _isAndroidSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> syncOnlineState({
    required bool isOnline,
    required bool hasActiveDelivery,
    int availableDeliveries = 0,
  }) async {
    if (!_isAndroidSupported) return;

    // A foreground service is needed while a delivery is actively tracked in
    // the background. Starting it solely because a courier is marked online
    // is both unnecessary (the app already receives realtime offers) and can
    // be rejected by Android/BlueStacks before the notification is attached.
    // That rejection kills the Flutter process and leaves the last route as a
    // blank screen. Keep the service strictly scoped to an active delivery.
    final shouldProtectCourier = hasActiveDelivery;
    if (!shouldProtectCourier) {
      await stop();
      return;
    }

    final title = hasActiveDelivery
        ? 'Deligo estafeta em entrega'
        : 'Deligo estafeta online';
    final body = hasActiveDelivery
        ? 'Protecao ativa para manter a entrega sincronizada.'
        : availableDeliveries > 0
        ? 'Protecao ativa enquanto aguardas $availableDeliveries pedido(s).'
        : 'Protecao ativa para receber novos pedidos sem atraso.';

    await start(title: title, body: body);
  }

  Future<void> start({required String title, required String body}) async {
    if (!_isAndroidSupported) return;
    try {
      await _channel.invokeMethod('start', {'title': title, 'body': body});
    } on MissingPluginException {
      // Android integration not available in this build flavor.
    } catch (error) {
      debugPrint('CourierForegroundService.start error: $error');
    }
  }

  Future<void> stop() async {
    if (!_isAndroidSupported) return;
    try {
      await _channel.invokeMethod('stop');
    } on MissingPluginException {
      // Android integration not available in this build flavor.
    } catch (error) {
      debugPrint('CourierForegroundService.stop error: $error');
    }
  }

  Future<bool> isIgnoringBatteryOptimizations() async {
    if (!_isAndroidSupported) return true;
    try {
      return await _channel.invokeMethod<bool>(
            'isIgnoringBatteryOptimizations',
          ) ??
          false;
    } on MissingPluginException {
      return true;
    } catch (error) {
      debugPrint(
        'CourierForegroundService.isIgnoringBatteryOptimizations error: $error',
      );
      return false;
    }
  }

  Future<int?> getBatteryLevel() async {
    if (!_isAndroidSupported) return null;
    try {
      return await _channel.invokeMethod<int>('getBatteryLevel');
    } on MissingPluginException {
      return null;
    } catch (error) {
      debugPrint('CourierForegroundService.getBatteryLevel error: $error');
      return null;
    }
  }

  Future<void> openBatteryOptimizationSettings() async {
    if (!_isAndroidSupported) return;
    try {
      await _channel.invokeMethod('openBatteryOptimizationSettings');
    } on MissingPluginException {
      // Android integration not available in this build flavor.
    } catch (error) {
      debugPrint(
        'CourierForegroundService.openBatteryOptimizationSettings error: $error',
      );
    }
  }
}
