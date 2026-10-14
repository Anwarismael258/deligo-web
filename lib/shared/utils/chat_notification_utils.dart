import 'dart:convert';

import 'notification_type_utils.dart';

class ChatNotificationUtils {
  static bool isUnreadChatNotification(Map<String, dynamic> notification) {
    return notification['read_at'] == null &&
        NotificationTypeUtils.canonicalize(notification['type']?.toString()) ==
            'MESSAGE_RECEIVED';
  }

  static bool matchesOrder(Map<String, dynamic> notification, String orderId) {
    if (orderId.trim().isEmpty) return false;
    if (NotificationTypeUtils.canonicalize(notification['type']?.toString()) !=
        'MESSAGE_RECEIVED') {
      return false;
    }

    final entityOrder = notification['entity_id']?.toString() ?? '';
    Map<String, dynamic> decodeMap(Object? value) {
      if (value is Map) return value.cast<String, dynamic>();
      if (value is String && value.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(value);
          if (decoded is Map) return decoded.cast<String, dynamic>();
        } catch (_) {
          // A malformed optional payload must not break the order list.
        }
      }
      return const {};
    }

    final metadata = decodeMap(notification['metadata']);
    final data = decodeMap(notification['data']);
    final metaOrder = metadata['order_id']?.toString() ?? '';
    final dataOrder = data['order_id']?.toString() ?? '';

    return entityOrder == orderId ||
        metaOrder == orderId ||
        dataOrder == orderId;
  }
}
