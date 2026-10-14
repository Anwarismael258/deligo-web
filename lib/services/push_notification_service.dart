import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/router/app_router.dart';
import '../config/app_env.dart';
import '../shared/utils/notification_type_utils.dart';
import 'app_voice_service.dart';
import 'courier_offer_feedback_deadline.dart';
import 'courier_foreground_service.dart';
import 'notification_event_identity.dart';
import 'notification_event.dart';
import 'critical_alert_controller.dart';
import 'notification_router_service.dart';
import 'sound_controller.dart';

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  final payload = response.payload;
  if (response.actionId?.isNotEmpty == true) {
    NotificationRouterService().handleNotificationAction(
      actionId: response.actionId!,
      payload: PushNotificationService.decodePayload(payload),
    );
    return;
  }
  NotificationRouterService().handlePayloadString(payload);
}

class PushNotificationService with WidgetsBindingObserver {
  static final PushNotificationService _instance =
      PushNotificationService._internal();
  static const String highImportanceChannelId = 'high_importance_v5';
  static const String courierDispatchChannelId = 'courier_dispatch_v5';
  static const String restaurantOrdersChannelId = 'restaurant_orders_v6';
  static const String clientAlertChannelId = 'client_alert_v5';
  static const String supportMessagesChannelId = 'support_messages_v2';
  static const String _criticalSoundName = 'platinum_1';
  static const String _restaurantOrderSoundName = 'platinum_1';
  static const String _normalSoundName = 'notification';
  static const String _courierAcceptActionId =
      NotificationRouterService.courierAcceptActionId;
  static const String _courierDismissActionId =
      NotificationRouterService.courierDismissActionId;

  factory PushNotificationService() => _instance;
  PushNotificationService._internal();

  SupabaseClient get _supabase => Supabase.instance.client;
  final AsyncSingleFlight _initializationFlight = AsyncSingleFlight();
  final AsyncSingleFlight _realtimeSubscriptionFlight = AsyncSingleFlight();
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  RealtimeChannel? _notificationChannel;
  bool _initialized = false;
  bool _lifecycleObserverRegistered = false;
  String? _realtimeUserId;
  String? _registeredUserId;
  String? _feedbackUserId;
  final NotificationFeedbackDeduplicator _feedbackDeduplicator =
      NotificationFeedbackDeduplicator();
  StreamSubscription<RemoteMessage>? _foregroundMessageSubscription;
  StreamSubscription<RemoteMessage>? _openedMessageSubscription;
  StreamSubscription<AuthState>? _authStateSubscription;
  StreamSubscription<String>? _tokenRefreshSubscription;

  AndroidNotificationChannel get _channel => AndroidNotificationChannel(
    highImportanceChannelId,
    'Notificacoes importantes',
    description: 'Pedidos, mensagens e entregas',
    importance: Importance.high,
    playSound: true,
    sound: const RawResourceAndroidNotificationSound(_normalSoundName),
    enableVibration: true,
  );

  AndroidNotificationChannel get _courierDispatchChannel =>
      AndroidNotificationChannel(
        courierDispatchChannelId,
        'Chamadas de entrega',
        description: 'Pedidos novos para estafetas com alerta forte',
        importance: Importance.max,
        playSound: true,
        sound: const RawResourceAndroidNotificationSound(
          _restaurantOrderSoundName,
        ),
        enableVibration: true,
      );

  AndroidNotificationChannel get _restaurantOrdersChannel =>
      AndroidNotificationChannel(
        restaurantOrdersChannelId,
        'Pedidos do restaurante',
        description: 'Novos pedidos pagos com toque forte',
        importance: Importance.high,
        playSound: true,
        sound: const RawResourceAndroidNotificationSound(
          _restaurantOrderSoundName,
        ),
        enableVibration: true,
      );

  AndroidNotificationChannel get _clientAlertChannel =>
      AndroidNotificationChannel(
        clientAlertChannelId,
        'Alertas fortes do cliente',
        description: 'Pedido pronto e estafeta atribuido com som forte',
        importance: Importance.high,
        playSound: true,
        sound: const RawResourceAndroidNotificationSound(
          _restaurantOrderSoundName,
        ),
        enableVibration: true,
      );

  AndroidNotificationChannel get _supportMessagesChannel =>
      AndroidNotificationChannel(
        supportMessagesChannelId,
        'Mensagens do suporte',
        description: 'Chats e tickets pendentes do suporte em tempo real',
        importance: Importance.defaultImportance,
        playSound: true,
        sound: const RawResourceAndroidNotificationSound(_normalSoundName),
        enableVibration: true,
      );

  static InitializationSettings _initializationSettings() {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    return const InitializationSettings(android: androidInit, iOS: darwinInit);
  }

  static Map<String, dynamic> decodePayload(String? payload) {
    if (payload == null || payload.trim().isEmpty) {
      return const <String, dynamic>{};
    }
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {}
    return const <String, dynamic>{};
  }

  static bool _isExpiredCourierOfferPayload(Map<dynamic, dynamic> payload) {
    if (!CourierOfferFeedbackDeadline.isCourierOfferPayload(payload)) {
      return false;
    }
    return CourierOfferFeedbackDeadline.fromCourierOfferPayload(
          payload,
          now: DateTime.now(),
        ) ==
        null;
  }

  static Future<void> _stopCourierOfferFeedbackIfMatching(
    Map<dynamic, dynamic> payload,
  ) async {
    final attemptId = CourierOfferFeedbackDeadline.attemptIdFromPayload(
      payload,
    );
    if (attemptId == null) return;
    final orderId = _entityIdFromAnyPayload(payload);
    await SoundController.instance.stopCourierDispatchLoop(
      orderId: orderId,
      attemptId: attemptId,
    );
  }

  static String? _entityIdFromAnyPayload(Map<dynamic, dynamic> payload) {
    for (final key in const ['entity_id', 'order_id', 'pedido_id']) {
      final value = payload[key]?.toString().trim();
      if (value?.isNotEmpty == true) return value;
    }
    for (final key in const ['metadata', 'data']) {
      var nested = payload[key];
      if (nested is String && nested.trim().startsWith('{')) {
        try {
          nested = jsonDecode(nested);
        } catch (_) {
          continue;
        }
      }
      if (nested is Map) {
        final value = _entityIdFromAnyPayload(nested);
        if (value != null) return value;
      }
    }
    return null;
  }

  static Future<void> handleBackgroundMessage(RemoteMessage message) async {
    final notificationId = message.data['id']?.toString();
    final type = NotificationTypeUtils.canonicalize(
      message.data['type']?.toString(),
    );
    final channel = message.data['channel']?.toString();
    if (_isExpiredCourierOfferPayload(message.data)) {
      final service = PushNotificationService();
      await service._ackNotificationState(
        notificationId,
        state: 'delivered',
        context: {
          'ack_source': 'expired_courier_offer_suppressed',
          'channel': channel,
          'type': type,
        },
      );
      return;
    }
    if (message.notification != null) {
      final service = PushNotificationService();
      await service._ackNotificationState(
        notificationId,
        state: 'delivered',
        context: {
          'ack_source': 'background_system_notification',
          'channel': channel,
          'type': type,
        },
      );
      return;
    }

    final title = message.data['title']?.toString().trim() ?? '';
    final body = message.data['body']?.toString().trim() ?? '';
    if (title.isEmpty || body.isEmpty) return;

    final service = PushNotificationService();
    final local = FlutterLocalNotificationsPlugin();
    await local.initialize(_initializationSettings());
    await service._createAndroidChannels(local);

    await local.show(
      notificationId?.hashCode ?? DateTime.now().millisecondsSinceEpoch,
      title,
      body,
      NotificationDetails(
        android: service._androidDetailsFor(type, channel),
        iOS: service._darwinDetailsFor(type, channel),
      ),
      payload: jsonEncode({...message.data, 'title': title, 'body': body}),
    );
    await service._ackNotificationState(
      notificationId,
      state: 'delivered',
      context: {
        'ack_source': 'background_data',
        'channel': channel,
        'type': type,
      },
    );
  }

  Future<void> initialize() {
    if (_initialized) {
      return _ensureRealtimeSubscription();
    }
    return _initializationFlight.run(_initializeInternal);
  }

  Future<void> dispose() async {
    await _foregroundMessageSubscription?.cancel();
    _foregroundMessageSubscription = null;
    await _openedMessageSubscription?.cancel();
    _openedMessageSubscription = null;
    await _authStateSubscription?.cancel();
    _authStateSubscription = null;
    await _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = null;
    final channel = _notificationChannel;
    _notificationChannel = null;
    _realtimeUserId = null;
    _feedbackDeduplicator.clear();
    _feedbackUserId = null;
    SoundController.instance.clearUserScopedAlertHistory();
    await SoundController.instance.stopRestaurantOrderAlert();
    await SoundController.instance.stopCourierDispatchLoop();
    if (channel != null) await _supabase.removeChannel(channel);
    _initialized = false;
  }

  Future<void> _initializeInternal() async {
    if (_initialized) {
      await _ensureRealtimeSubscription();
      return;
    }
    _syncFeedbackUser(_supabase.auth.currentUser?.id);
    debugPrint('PushNotificationService: init');

    await _local.initialize(
      _initializationSettings(),
      onDidReceiveNotificationResponse: (response) async {
        if (response.actionId?.isNotEmpty == true) {
          await NotificationRouterService().handleNotificationAction(
            actionId: response.actionId!,
            payload: decodePayload(response.payload),
          );
          return;
        }
        await NotificationRouterService().handlePayloadString(response.payload);
      },
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    final launchDetails = await _local.getNotificationAppLaunchDetails();
    final launchResponse = launchDetails?.notificationResponse;
    if (launchDetails?.didNotificationLaunchApp == true &&
        launchResponse != null) {
      Future<void>.delayed(const Duration(milliseconds: 650), () async {
        if (launchResponse.actionId?.isNotEmpty == true) {
          await NotificationRouterService().handleNotificationAction(
            actionId: launchResponse.actionId!,
            payload: decodePayload(launchResponse.payload),
          );
          return;
        }
        await NotificationRouterService().handlePayloadString(
          launchResponse.payload,
        );
      });
    }

    await _createAndroidChannels();

    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
          alert: false,
          badge: true,
          sound: false,
        );

    final permission = await FirebaseMessaging.instance.requestPermission();
    await FirebaseMessaging.instance.setAutoInitEnabled(true);

    _foregroundMessageSubscription ??= FirebaseMessaging.onMessage.listen(
      _showForegroundNotification,
    );
    _openedMessageSubscription ??= FirebaseMessaging.onMessageOpenedApp.listen((
      message,
    ) async {
      await NotificationRouterService().handlePayloadMap(message.data);
    });

    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      Future<void>.delayed(const Duration(milliseconds: 650), () async {
        await NotificationRouterService().handlePayloadMap(initialMessage.data);
      });
    }

    _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = FirebaseMessaging.instance.onTokenRefresh
        .listen((token) async {
          await registerFcmToken(token: token);
        });

    if (permission.authorizationStatus == AuthorizationStatus.authorized ||
        permission.authorizationStatus == AuthorizationStatus.provisional) {
      await registerFcmToken();
    }

    _authStateSubscription ??= _supabase.auth.onAuthStateChange.listen((_) {
      final user = _supabase.auth.currentUser;
      _syncFeedbackUser(user?.id);
      final previousUserId = _registeredUserId;
      if (user == null) {
        if (previousUserId != null && previousUserId.isNotEmpty) {
          clearFcmToken(userId: previousUserId);
        }
        unawaited(SoundController.instance.stopRestaurantOrderAlert());
        unawaited(SoundController.instance.stopCourierDispatchLoop());
        unawaited(CourierForegroundService.instance.stop());
      } else {
        if (previousUserId != null &&
            previousUserId.isNotEmpty &&
            previousUserId != user.id) {
          clearFcmToken(userId: previousUserId);
          unawaited(SoundController.instance.stopRestaurantOrderAlert());
          unawaited(SoundController.instance.stopCourierDispatchLoop());
          unawaited(CourierForegroundService.instance.stop());
        }
        registerFcmToken();
      }
      unawaited(_ensureRealtimeSubscription());
    });
    await _ensureRealtimeSubscription();

    _initialized = true;
    if (!_lifecycleObserverRegistered) {
      WidgetsBinding.instance.addObserver(this);
      _lifecycleObserverRegistered = true;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !_initialized) return;
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    // Android can rotate the FCM token while the app is backgrounded. Refresh
    // it on resume so the server always has a current device target for offers
    // delivered while the app is closed or the screen is locked.
    unawaited(registerFcmToken());
  }

  Future<String?> registerFcmToken({String? token}) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;
    final fcm = token ?? await FirebaseMessaging.instance.getToken();
    if (fcm == null) return null;

    try {
      await _upsertUserPushToken(userId: user.id, token: fcm);
    } catch (error) {
      debugPrint(
        'PushNotificationService: erro ao salvar token multi-device $error',
      );
    }

    try {
      await _supabase
          .from('profiles')
          .update({
            'fcm_token': fcm,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', user.id);
      _registeredUserId = user.id;
      debugPrint('PushNotificationService: token ativo para ${user.id}');
      await _ensureRealtimeSubscription();
      return fcm;
    } catch (e) {
      debugPrint('PushNotificationService: erro ao salvar token $e');
      return null;
    }
  }

  Future<Map<String, String>> operationalDiagnostics({
    bool refreshToken = false,
  }) async {
    final user = _supabase.auth.currentUser;
    final permission = await FirebaseMessaging.instance
        .getNotificationSettings();
    String? fcm;
    if (user != null && refreshToken) {
      fcm = await registerFcmToken();
    } else {
      fcm = await FirebaseMessaging.instance.getToken();
    }

    Map<String, dynamic>? tokenRow;
    if (user != null && fcm != null && fcm.isNotEmpty) {
      try {
        final row = await _supabase
            .from('user_push_tokens')
            .select('platform, is_active, last_seen_at')
            .eq('user_id', user.id)
            .eq('token', fcm)
            .maybeSingle();
        if (row != null) tokenRow = Map<String, dynamic>.from(row);
      } catch (_) {}
    }

    final tokenSuffix = fcm == null || fcm.isEmpty
        ? ''
        : fcm.substring(fcm.length > 10 ? fcm.length - 10 : 0);
    final realtimeActive =
        user != null &&
        _realtimeUserId == user.id &&
        _notificationChannel != null;
    return {
      'sessao': user == null ? 'Sem login' : 'Com login',
      'user_id': user?.id ?? '',
      'permissao_android': permission.authorizationStatus.name,
      'token_fcm': tokenSuffix.isEmpty ? 'Ausente' : '...$tokenSuffix',
      'token_no_banco': tokenRow == null
          ? 'Nao encontrado'
          : (tokenRow['is_active'] == true ? 'Ativo' : 'Inativo'),
      'plataforma': tokenRow?['platform']?.toString() ?? '-',
      'ultimo_token': tokenRow?['last_seen_at']?.toString() ?? '-',
      'realtime_push': realtimeActive ? 'Conectado' : 'Nao conectado',
      'servico_push': _initialized ? 'Inicializado' : 'Nao inicializado',
    };
  }

  Future<void> clearFcmToken({String? userId}) async {
    final resolvedUserId = userId ?? _supabase.auth.currentUser?.id;
    if (resolvedUserId == null || resolvedUserId.isEmpty) return;
    try {
      final currentToken = await FirebaseMessaging.instance.getToken();
      if (currentToken != null && currentToken.isNotEmpty) {
        await _deactivateUserPushToken(
          userId: resolvedUserId,
          token: currentToken,
        );
      }
      await _supabase
          .from('profiles')
          .update({
            'fcm_token': null,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', resolvedUserId);
      if (_registeredUserId == resolvedUserId) {
        _registeredUserId = null;
      }
    } catch (error) {
      debugPrint('PushNotificationService: erro ao limpar token $error');
    }
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    final type = NotificationTypeUtils.canonicalize(
      message.data['type']?.toString(),
    );
    final notificationId = message.data['id']?.toString();
    final priority = message.data['priority']?.toString();
    final channel = message.data['channel']?.toString();
    if (_isExpiredCourierOfferPayload(message.data)) {
      await _stopCourierOfferFeedbackIfMatching(message.data);
      await _ackNotificationState(
        notificationId,
        state: 'delivered',
        context: {
          'ack_source': 'expired_courier_offer_suppressed',
          'channel': channel,
          'type': type,
        },
      );
      return;
    }
    final title =
        message.notification?.title?.trim() ??
        message.data['title']?.toString().trim() ??
        '';
    final body =
        message.notification?.body?.trim() ??
        message.data['body']?.toString().trim() ??
        '';
    if (title.isEmpty && body.isEmpty) return;
    await _handleForegroundFeedback(
      payload: message.data,
      type: type,
      channel: channel,
      title: title,
      body: body,
      priority: priority,
      notificationId: notificationId,
      ackSource: 'foreground_fcm_in_app',
    );
  }

  Future<void> _handleForegroundFeedback({
    required Map<dynamic, dynamic> payload,
    required String type,
    required String? channel,
    required String title,
    required String body,
    required String? priority,
    required String? notificationId,
    required String ackSource,
  }) async {
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    _syncFeedbackUser(_supabase.auth.currentUser?.id);
    if (CourierOfferFeedbackDeadline.isCourierOfferPayload(payload) &&
        _isExpiredCourierOfferPayload(payload)) {
      await _stopCourierOfferFeedbackIfMatching(payload);
      await _ackNotificationState(
        notificationId,
        state: 'delivered',
        context: {
          'ack_source': 'invalid_or_expired_courier_offer_suppressed',
          'channel': channel,
          'type': type,
        },
      );
      return;
    }
    final normalizedPayload = Map<String, dynamic>.fromEntries(
      payload.entries.map(
        (entry) => MapEntry(entry.key.toString(), entry.value),
      ),
    );
    final entityId = _entityIdFromPayload(normalizedPayload);
    await _stopRelatedCriticalFeedback(type, entityId);
    final identityPayload = <String, dynamic>{
      ...Map<String, dynamic>.fromEntries(
        payload.entries.map(
          (entry) => MapEntry(entry.key.toString(), entry.value),
        ),
      ),
      'id': notificationId ?? payload['id'],
      'type': type,
      'entity_id': entityId,
    };
    final identity =
        NotificationEventIdentity.fromPayload(identityPayload) ??
        _buildDedupeKey(
          notificationId: notificationId,
          type: type,
          entityId: entityId,
        );
    if (!_markNotificationHandled(identity)) return;

    final suppressed = _shouldSuppressForegroundHeadsUp(
      type,
      channel,
      title: title,
      body: body,
    );
    final critical = _isCriticalActionableEvent(type, channel);
    if (!suppressed || critical) {
      await _playInAppFeedback(
        type,
        channel,
        entityId: entityId,
        dispatchAttemptId: _payloadString(
          identityPayload,
          'dispatch_attempt_id',
        ),
        dispatchExpiresAt: _dispatchExpiry(identityPayload),
      );
    }
    if (!suppressed && !_shouldSuppressForegroundVoice(type, channel)) {
      await AppVoiceService.instance.speakNotification(
        type: type,
        title: title,
        body: body,
        notificationId: notificationId,
        channel: channel,
        priority: priority,
      );
    }
    await _ackNotificationState(
      notificationId,
      state: 'delivered',
      context: {'ack_source': ackSource, 'channel': channel, 'type': type},
    );
  }

  Future<void> _stopRelatedCriticalFeedback(
    String type,
    String? entityId,
  ) async {
    if (entityId == null || entityId.trim().isEmpty) return;
    switch (type) {
      case 'ORDER_ACCEPTED':
      case 'ORDER_CONFIRMED_BY_RESTAURANT':
      case 'ORDER_PREPARING':
        await SoundController.instance.stopRestaurantOrderAlert(
          orderId: entityId,
        );
        break;
      case 'DRIVER_ASSIGNED':
      case 'ORDER_PICKED_UP':
      case 'ORDER_CANCELLED':
      case 'ORDER_REJECTED':
      case 'ORDER_EXPIRED':
      case 'DELIVERY_UNAVAILABLE':
      case 'ORDER_COMPLETED':
      case 'ORDER_DELIVERED':
        await SoundController.instance.stopCourierDispatchLoop(
          orderId: entityId,
        );
        await SoundController.instance.stopRestaurantOrderAlert(
          orderId: entityId,
        );
        break;
      default:
        break;
    }
  }

  String? _entityIdFromPayload(Map<String, dynamic> payload) {
    for (final key in const ['entity_id', 'order_id', 'pedido_id']) {
      final value = payload[key]?.toString().trim();
      if (value?.isNotEmpty == true) return value;
    }
    for (final key in const ['metadata', 'data', 'payload']) {
      var nested = payload[key];
      if (nested is String && nested.trim().startsWith('{')) {
        nested = decodePayload(nested);
      }
      if (nested is Map) {
        final resolved = _entityIdFromPayload(
          Map<String, dynamic>.fromEntries(
            nested.entries.map(
              (entry) => MapEntry(entry.key.toString(), entry.value),
            ),
          ),
        );
        if (resolved != null) return resolved;
      }
    }
    return null;
  }

  Future<void> showSupportMessageAlert({
    required String ticketId,
    required String senderName,
    required String body,
    String? eventId,
  }) async {
    if (!_initialized) {
      await initialize();
    }
    final trimmedBody = body.trim();
    if (trimmedBody.isEmpty) return;
    final cleanSender = senderName.trim();
    final title = 'Nova mensagem no suporte';
    final messageBody = cleanSender.isEmpty
        ? trimmedBody
        : '$cleanSender: $trimmedBody';
    final payload = <String, dynamic>{
      'type': 'SUPPORT_MESSAGE_RECEIVED',
      'channel': 'support',
      'entity_id': ticketId,
      'support_ticket_id': ticketId,
      'title': title,
      'body': messageBody,
    };
    await _handleForegroundFeedback(
      payload: {
        ...payload,
        if (eventId?.trim().isNotEmpty == true) 'event_id': eventId!.trim(),
      },
      type: 'SUPPORT_MESSAGE_RECEIVED',
      channel: 'support',
      title: title,
      body: messageBody,
      priority: 'NORMAL',
      notificationId: null,
      ackSource: 'support_chat_in_app',
    );
  }

  Future<void> _ensureRealtimeSubscription() =>
      _realtimeSubscriptionFlight.run(_ensureRealtimeSubscriptionInternal);

  Future<void> _ensureRealtimeSubscriptionInternal() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == _realtimeUserId && _notificationChannel != null) return;

    if (_notificationChannel != null) {
      await _supabase.removeChannel(_notificationChannel!);
      _notificationChannel = null;
    }

    _realtimeUserId = userId;
    if (userId == null || userId.isEmpty) return;

    _notificationChannel = _supabase
        .channel('push_notifications_$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'push_notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) async {
            final row = Map<String, dynamic>.from(payload.newRecord);
            final title = row['title']?.toString() ?? 'DeliGo';
            final body = row['body']?.toString() ?? '';
            final type = NotificationTypeUtils.canonicalize(
              row['type']?.toString(),
            );
            final priority = row['priority']?.toString();
            final channel = row['channel']?.toString();
            if (_isExpiredCourierOfferPayload(row)) {
              await _stopCourierOfferFeedbackIfMatching(row);
              return;
            }
            await _handleForegroundFeedback(
              payload: row,
              type: type,
              channel: channel,
              title: title,
              body: body,
              priority: priority,
              notificationId: row['id']?.toString(),
              ackSource: 'realtime_in_app',
            );
          },
        )
        .subscribe();

    // If auth changed while channel creation was awaiting, serialize a follow-up
    // sync so the old user channel cannot remain active after relogin.
    if (_supabase.auth.currentUser?.id != _realtimeUserId) {
      Timer.run(() => unawaited(_ensureRealtimeSubscription()));
    }
  }

  AndroidNotificationDetails _androidDetailsFor(String type, String? channel) {
    if (_isSupportMessage(type, channel)) {
      return AndroidNotificationDetails(
        _supportMessagesChannel.id,
        _supportMessagesChannel.name,
        channelDescription: _supportMessagesChannel.description,
        icon: '@mipmap/ic_launcher',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        category: AndroidNotificationCategory.message,
        fullScreenIntent: false,
        playSound: true,
        enableVibration: false,
        sound: const RawResourceAndroidNotificationSound(_normalSoundName),
        ticker: 'Nova mensagem no suporte',
        visibility: NotificationVisibility.private,
      );
    }
    if (_isRestaurantOrderAlert(type, channel)) {
      return AndroidNotificationDetails(
        _restaurantOrdersChannel.id,
        _restaurantOrdersChannel.name,
        channelDescription: _restaurantOrdersChannel.description,
        icon: '@mipmap/ic_launcher',
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.event,
        // Normal heads-up notification only. Android decides whether the
        // display wakes; commercial orders must never use full-screen intent.
        fullScreenIntent: false,
        playSound: true,
        enableVibration: true,
        sound: const RawResourceAndroidNotificationSound(
          _restaurantOrderSoundName,
        ),
        vibrationPattern: Int64List.fromList([0, 500, 180, 700, 180, 500]),
        ticker: 'Novo pedido pago',
        visibility: NotificationVisibility.private,
      );
    }
    if (type == 'ORDER_READY_FOR_PICKUP') {
      return AndroidNotificationDetails(
        _clientAlertChannel.id,
        _clientAlertChannel.name,
        channelDescription: _clientAlertChannel.description,
        icon: '@mipmap/ic_launcher',
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.event,
        fullScreenIntent: false,
        playSound: true,
        enableVibration: true,
        sound: const RawResourceAndroidNotificationSound(_criticalSoundName),
        vibrationPattern: Int64List.fromList([0, 500, 180, 700]),
        ticker: 'Pedido pronto para retirada',
        visibility: NotificationVisibility.private,
      );
    }
    if (_isClientAlert(type, channel)) {
      return AndroidNotificationDetails(
        _clientAlertChannel.id,
        _clientAlertChannel.name,
        channelDescription: _clientAlertChannel.description,
        icon: '@mipmap/ic_launcher',
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.status,
        fullScreenIntent: false,
        playSound: true,
        enableVibration: true,
        sound: const RawResourceAndroidNotificationSound(_normalSoundName),
        vibrationPattern: Int64List.fromList([0, 500, 180, 700, 180, 500]),
        ticker: 'Atualizacao urgente do seu pedido',
        visibility: NotificationVisibility.private,
      );
    }
    if (_isCourierDispatch(type, channel)) {
      return AndroidNotificationDetails(
        _courierDispatchChannel.id,
        _courierDispatchChannel.name,
        channelDescription: _courierDispatchChannel.description,
        icon: '@mipmap/ic_launcher',
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.call,
        // Normal heads-up notification only. Android decides whether the
        // display wakes; delivery offers must never use full-screen intent.
        fullScreenIntent: false,
        playSound: true,
        enableVibration: true,
        sound: const RawResourceAndroidNotificationSound(_criticalSoundName),
        vibrationPattern: Int64List.fromList([0, 700, 220, 900, 220, 700]),
        ticker: 'Novo pedido perto de voce',
        visibility: NotificationVisibility.private,
        actions: <AndroidNotificationAction>[
          AndroidNotificationAction(
            _courierAcceptActionId,
            'Aceitar',
            showsUserInterface: true,
            cancelNotification: true,
          ),
          AndroidNotificationAction(
            _courierDismissActionId,
            'Recusar',
            showsUserInterface: true,
            cancelNotification: true,
          ),
        ],
      );
    }

    return AndroidNotificationDetails(
      _channel.id,
      _channel.name,
      channelDescription: _channel.description,
      icon: '@mipmap/ic_launcher',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.status,
      playSound: true,
      enableVibration: true,
      ticker: 'Atualizacao importante da sua conta',
      visibility: NotificationVisibility.private,
    );
  }

  DarwinNotificationDetails _darwinDetailsFor(String type, String? channel) {
    return const DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
  }

  Future<void> _playInAppFeedback(
    String type,
    String? channel, {
    String? entityId,
    String? dispatchAttemptId,
    DateTime? dispatchExpiresAt,
  }) async {
    final centralEvent = NotificationEvent.fromPayload({
      'type': type,
      'channel': channel,
      'entity_id': entityId,
      'dispatch_attempt_id': dispatchAttemptId,
      'dispatch_expires_at': dispatchExpiresAt?.toIso8601String(),
    });
    if (_isCourierDispatch(type, channel)) {
      await CriticalAlertController.instance.start(centralEvent);
      return;
    }
    if (type == 'NEW_ORDER' || type == 'NEW_PAID_ORDER') {
      await CriticalAlertController.instance.start(centralEvent);
      return;
    }
    if (type == 'ORDER_ACCEPTED') {
      await SoundController.instance.orderAccepted();
      return;
    }
    if (type == 'PAYMENT_FAILED' ||
        type == 'ORDER_REJECTED' ||
        type == 'ORDER_CANCELLED' ||
        type == 'ORDER_EXPIRED' ||
        type == 'ORDER_DISPUTED' ||
        type == 'kyc_rejected') {
      await SoundController.instance.error();
      return;
    }
    if (type == 'PAYMENT_CONFIRMED' ||
        type == 'ORDER_COMPLETED' ||
        type == 'ORDER_AUTO_COMPLETED' ||
        type == 'REFUND_COMPLETED' ||
        type == 'PAYMENT_RELEASED' ||
        type == 'kyc_approved') {
      await SoundController.instance.success();
      return;
    }
    if (type == 'ORDER_READY' || type == 'DRIVER_ASSIGNED') {
      await SoundController.instance.newOrderDriver();
      return;
    }
    if (type == 'ORDER_PREPARING') {
      await SoundController.instance.preparing();
      return;
    }
    if (type == 'DRIVER_ASSIGNED') {
      await SoundController.instance.driverAssigned();
      return;
    }
    if (type == 'DRIVER_ARRIVED') {
      await SoundController.instance.driverArriving();
      return;
    }
    if (type == 'ORDER_PICKED_UP') {
      await SoundController.instance.driverAssigned();
      return;
    }
    if (type == 'MESSAGE_RECEIVED' || type == 'SUPPORT_MESSAGE_RECEIVED') {
      await SoundController.instance.messageReceived();
      return;
    }
    if (type == 'ORDER_DELIVERED') {
      await SoundController.instance.delivered();
      return;
    }
    if (type == 'SUPPORT_UPDATED' && channel == 'support') {
      await SoundController.instance.newDispute();
      return;
    }
    if (type == 'REFUND_STARTED') {
      await SoundController.instance.notification();
      return;
    }
    if (type == 'DELIVERY_OTP_ISSUED' ||
        type == 'DELIVERY_OTP_REGENERATED' ||
        type == 'DELIVERY_SLA_EXCEEDED') {
      await SoundController.instance.notification();
      return;
    }
    if (type == 'DELIVERY_EXTENSION_REQUESTED') {
      await SoundController.instance.notification();
      return;
    }
    await SoundController.instance.notification();
  }

  bool _isCourierDispatch(String type, String? channel) {
    return type == 'DELIVERY_OPPORTUNITY' ||
        type == 'NEW_DRIVER_ORDER' ||
        channel == 'courier_dispatch';
  }

  bool _isCriticalActionableEvent(String type, String? channel) {
    return _isCourierDispatch(type, channel) ||
        _isRestaurantOrderAlert(type, channel);
  }

  String? _payloadString(Map<String, dynamic> payload, String key) {
    final direct = payload[key]?.toString().trim();
    if (direct?.isNotEmpty == true) return direct;
    for (final name in const ['metadata', 'data']) {
      var nestedPayload = payload[name];
      if (nestedPayload is String) {
        nestedPayload = decodePayload(nestedPayload);
      }
      if (nestedPayload is Map) {
        final nested = nestedPayload[key]?.toString().trim();
        if (nested?.isNotEmpty == true) return nested;
      }
    }
    return null;
  }

  DateTime? _dispatchExpiry(Map<String, dynamic> payload) {
    if (!CourierOfferFeedbackDeadline.isCourierOfferPayload(payload)) {
      return null;
    }
    return CourierOfferFeedbackDeadline.fromCourierOfferPayload(
      payload,
      now: DateTime.now(),
    );
  }

  bool _isSupportMessage(String type, String? channel) {
    return type == 'SUPPORT_MESSAGE_RECEIVED' ||
        (type == 'MESSAGE_RECEIVED' && channel == 'support') ||
        channel == 'support_messages';
  }

  bool _isClientAlert(String type, String? channel) {
    return type == 'ORDER_READY' ||
        type == 'ORDER_READY_FOR_PICKUP' ||
        type == 'DRIVER_ASSIGNED' ||
        channel == 'client_alert';
  }

  bool _isRestaurantOrderAlert(String type, String? channel) {
    return type == 'NEW_ORDER' ||
        type == 'NEW_PAID_ORDER' ||
        channel == 'restaurant_order_alert';
  }

  bool _shouldSuppressForegroundHeadsUp(
    String type,
    String? channel, {
    String? title,
    String? body,
  }) {
    if (_isTimeoutRefundPopup(type, title: title, body: body)) {
      return true;
    }
    if (_shouldSuppressOperationalForegroundFeedback(type, channel)) {
      return true;
    }
    return false;
  }

  bool _shouldSuppressForegroundVoice(String type, String? channel) {
    return _shouldSuppressOperationalForegroundFeedback(type, channel);
  }

  bool _shouldSuppressOperationalForegroundFeedback(
    String type,
    String? channel,
  ) {
    if (!_isOperationalForegroundType(type, channel)) return false;
    final currentUri = AppRouter.router.routeInformationProvider.value.uri;
    final path = currentUri.path;
    return path.startsWith('/client-dashboard') ||
        path.startsWith('/courier-dashboard') ||
        path.startsWith('/restaurant-dashboard') ||
        path.startsWith('/tracking/') ||
        path.startsWith('/order/');
  }

  bool _isOperationalForegroundType(String type, String? channel) {
    switch (type) {
      case 'ORDER_ACCEPTED':
      case 'ORDER_PREPARING':
      case 'ORDER_READY':
      case 'DRIVER_ASSIGNED':
      case 'DRIVER_ARRIVED':
      case 'ORDER_PICKED_UP':
      case 'ORDER_DELIVERED':
      case 'ORDER_COMPLETED':
      case 'ORDER_AUTO_COMPLETED':
      case 'ORDER_READY_FOR_PICKUP':
      case 'NEW_DRIVER_ORDER':
      case 'DELIVERY_OPPORTUNITY':
      case 'NEW_ORDER':
      case 'NEW_PAID_ORDER':
        return true;
      default:
        return false;
    }
  }

  bool _isTimeoutRefundPopup(String type, {String? title, String? body}) {
    if (type != 'REFUND_COMPLETED') return false;
    final normalizedTitle = title?.trim().toLowerCase() ?? '';
    final normalizedBody = body?.trim().toLowerCase() ?? '';
    return normalizedTitle.contains('pedido nao confirmado a tempo') ||
        normalizedBody.contains('o valor voltou para a sua conta');
  }

  String _buildDedupeKey({
    String? notificationId,
    String? type,
    String? entityId,
  }) {
    final id = notificationId?.trim() ?? '';
    final normalizedType = type?.trim() ?? '';
    final normalizedEntity = entityId?.trim() ?? '';
    if (id.isNotEmpty && normalizedType.isNotEmpty) {
      return '$id|$normalizedType|$normalizedEntity';
    }
    // Without a stable event/notification id we cannot safely distinguish a
    // retransmission from a legitimate second event on the same entity.
    return '';
  }

  bool _markNotificationHandled(String key) {
    return _feedbackDeduplicator.claim(key);
  }

  void _syncFeedbackUser(String? userId) {
    if (_feedbackUserId == userId) return;
    final previousUserId = _feedbackUserId;
    _feedbackDeduplicator.clear();
    SoundController.instance.clearUserScopedAlertHistory();
    _feedbackUserId = userId;
    if (previousUserId != null) {
      unawaited(SoundController.instance.stopRestaurantOrderAlert());
      unawaited(SoundController.instance.stopCourierDispatchLoop());
    }
  }

  Future<void> _ackNotificationState(
    String? notificationId, {
    required String state,
    Map<String, dynamic>? context,
  }) async {
    final normalizedId = notificationId?.trim() ?? '';
    if (normalizedId.isEmpty) return;

    try {
      await _ensureSupabaseReady();
      await _supabase.rpc(
        'ack_push_notification_delivery',
        params: {
          'p_notification_id': normalizedId,
          'p_state': state,
          'p_context': context ?? const <String, dynamic>{},
        },
      );
    } catch (error) {
      debugPrint('PushNotificationService ack error for $normalizedId: $error');
    }
  }

  Future<void> _ensureSupabaseReady() async {
    try {
      Supabase.instance.client;
      return;
    } catch (_) {
      // Fall through and initialize for background isolates.
    }

    final supabaseUrl = AppEnv.supabaseUrl.trim();
    final supabaseAnonKey = AppEnv.supabaseAnonKey.trim();
    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) return;

    try {
      await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
    } catch (_) {
      // Another isolate may have initialized it already.
    }
  }

  Future<void> _upsertUserPushToken({
    required String userId,
    required String token,
  }) async {
    final platform = kIsWeb ? 'web' : defaultTargetPlatform.name;
    await _supabase.from('user_push_tokens').upsert({
      'user_id': userId,
      'token': token,
      'device_id': platform,
      'platform': platform,
      'is_active': true,
      'last_seen_at': DateTime.now().toIso8601String(),
    }, onConflict: 'token');
  }

  Future<void> _deactivateUserPushToken({
    required String userId,
    required String token,
  }) async {
    await _supabase
        .from('user_push_tokens')
        .update({
          'is_active': false,
          'last_seen_at': DateTime.now().toIso8601String(),
        })
        .eq('user_id', userId)
        .eq('token', token);
  }

  Future<void> _createAndroidChannels([
    FlutterLocalNotificationsPlugin? plugin,
  ]) async {
    final local = plugin ?? _local;
    await local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_channel);
    await local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_courierDispatchChannel);
    await local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_restaurantOrdersChannel);
    await local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_clientAlertChannel);
    await local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_supportMessagesChannel);
  }
}
