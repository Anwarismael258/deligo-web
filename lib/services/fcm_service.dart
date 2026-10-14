import 'package:flutter/foundation.dart';
// lib/services/fcm_service.dart
// Stub implementation - Firebase removido para evitar crashes
// O app funciona normalmente sem FCM

class FCMService {
  static final FCMService _instance = FCMService._internal();
  factory FCMService() => _instance;
  FCMService._internal();

  /// Inicializar FCM (stub)
  Future<void> initialize() async {
    debugPrint('FCMService: Firebase removido - FCM desativado');
  }

  /// Inscrever em topic (stub)
  Future<void> subscribeToZone(String zoneId) async {
    // Stub - nao faz nada
  }

  /// Inscrever em topic de restaurante (stub)
  Future<void> subscribeToRestaurant(String restaurantId) async {
    // Stub - nao faz nada
  }

  /// Inscrever em topic de entregador (stub)
  Future<void> subscribeToCourier(String courierId) async {
    // Stub - nao faz nada
  }

  /// Inscrever em topic de pedidos do cliente (stub)
  Future<void> subscribeToClientOrders(String clientId) async {
    // Stub - nao faz nada
  }

  /// Cancelar inscricao em topic (stub)
  Future<void> unsubscribeFromTopic(String topic) async {
    // Stub - nao faz nada
  }

  /// Inscrever em todos os topics relevantes apos login (stub)
  Future<void> subscribeToRelevantTopics(
    String role,
    String userId, {
    String? zoneId,
  }) async {
    // Stub - nao faz nada
  }

  /// Configurar handler para abrir notificacao (stub)
  void configureNotificationTap(Function(dynamic) onTap) {
    // Stub - nao faz nada
  }

  /// Obter token atual (stub)
  Future<String?> getToken() async {
    return null;
  }

  /// Deletar token (logout) (stub)
  Future<void> deleteToken() async {
    // Stub - nao faz nada
  }
}






