import '../config/app_env.dart';

class PublicShareService {
  PublicShareService._();

  static final PublicShareService instance = PublicShareService._();

  bool get hasWebBaseUrl =>
      AppEnv.deligoShareBaseUrl.isNotEmpty || AppEnv.appShareBaseUrl.isNotEmpty;

  String get _baseUrl {
    final configured = AppEnv.deligoShareBaseUrl.isNotEmpty
        ? AppEnv.deligoShareBaseUrl
        : AppEnv.appShareBaseUrl;
    if (configured.isEmpty) return '';
    return configured.endsWith('/')
        ? configured.substring(0, configured.length - 1)
        : configured;
  }

  String restaurantLink(String restaurantId, {String? orderId}) {
    final orderQuery = orderId != null && orderId.trim().isNotEmpty
        ? '?orderId=$orderId'
        : '';
    return 'https://deligotriunfal.co.mz/r/$restaurantId$orderQuery';
  }

  String dishLink({required String restaurantId, required String dishId}) {
    if (hasWebBaseUrl) {
      return '$_baseUrl/restaurant/$restaurantId?dish=$dishId';
    }
    return 'deligo://restaurant/$restaurantId?dish=$dishId';
  }

  String courierLink(String courierId, {String? orderId}) {
    final orderQuery = orderId != null && orderId.trim().isNotEmpty
        ? '?orderId=$orderId'
        : '';
    if (hasWebBaseUrl) {
      return '$_baseUrl/courier/$courierId$orderQuery';
    }
    return 'deligo://courier/$courierId$orderQuery';
  }

  String restaurantMessage({
    required String restaurantName,
    required String link,
  }) {
    return 'Conhece $restaurantName na DeliGo.\nVeja o perfil aqui: $link';
  }

  String dishMessage({
    required String dishName,
    required String restaurantName,
    required String link,
  }) {
    return 'Olha este prato na DeliGo: $dishName de $restaurantName.\nLink direto: $link';
  }

  String courierMessage({required String courierName, required String link}) {
    return 'Veja o perfil do estafeta $courierName na DeliGo.\nLink direto: $link';
  }
}
