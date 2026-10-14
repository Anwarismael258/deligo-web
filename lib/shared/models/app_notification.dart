class AppNotification {
  final String id;
  final String userId;
  final String type;
  final String title;
  final String body;
  final String? action;
  final String? entityId;
  final String priority;
  final String channel;
  final DateTime createdAt;
  final DateTime? readAt;
  final Map<String, dynamic> metadata;

  const AppNotification({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    required this.body,
    required this.priority,
    required this.channel,
    required this.createdAt,
    this.action,
    this.entityId,
    this.readAt,
    this.metadata = const <String, dynamic>{},
  });

  factory AppNotification.fromMap(Map<String, dynamic> map) {
    return AppNotification(
      id: map['id']?.toString() ?? '',
      userId: map['user_id']?.toString() ?? '',
      type: map['type']?.toString() ?? 'SYSTEM_ALERT',
      title: map['title']?.toString() ?? 'DeliGo',
      body: map['body']?.toString() ?? '',
      action: map['action']?.toString(),
      entityId: map['entity_id']?.toString(),
      priority: map['priority']?.toString() ?? 'NORMAL',
      channel: map['channel']?.toString() ?? 'system',
      createdAt:
          DateTime.tryParse(map['created_at']?.toString() ?? '') ??
          DateTime.now(),
      readAt: DateTime.tryParse(map['read_at']?.toString() ?? ''),
      metadata:
          (map['metadata'] as Map?)?.cast<String, dynamic>() ??
          (map['data'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{},
    );
  }
}
