class Message {
  final String id;
  final String orderId;
  final String senderId;
  final String senderName;
  final String senderRole; // 'client', 'restaurant', 'courier'
  final String text;
  final String? attachmentUrl;
  final String? attachmentType;
  final DateTime timestamp;
  final DateTime? deliveredAt;
  final DateTime? readAt;

  Message({
    required this.id,
    required this.orderId,
    required this.senderId,
    required this.senderName,
    required this.senderRole,
    required this.text,
    this.attachmentUrl,
    this.attachmentType,
    required this.timestamp,
    this.deliveredAt,
    this.readAt,
  });

  factory Message.fromMap(Map<String, dynamic> map) {
    return Message(
      id: map['id'] as String,
      orderId: map['order_id'] as String,
      senderId: map['sender_id'] as String,
      senderName: map['sender_name'] as String? ?? '',
      senderRole: map['sender_role'] as String? ?? 'client',
      text: (map['text'] ?? map['message'] ?? '') as String,
      attachmentUrl: map['attachment_url'] as String?,
      attachmentType: map['attachment_type'] as String?,
      timestamp: DateTime.parse(map['created_at'] as String),
      deliveredAt: map['delivered_at'] != null
          ? DateTime.tryParse(map['delivered_at'] as String)
          : null,
      readAt: map['read_at'] != null
          ? DateTime.tryParse(map['read_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'order_id': orderId,
      'sender_id': senderId,
      'sender_name': senderName,
      'sender_role': senderRole,
      'text': text,
      'attachment_url': attachmentUrl,
      'attachment_type': attachmentType,
    };
  }
}





