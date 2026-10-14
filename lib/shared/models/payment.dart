class Payment {
  final String id;
  final double amount;
  final String userMethod; // mpesa | emola
  final String status; // pending | paid | failed
  final String instructions; // USSD ou QR instructions
  final String? orderId;
  final DateTime createdAt;

  Payment({
    required this.id,
    required this.amount,
    required this.userMethod,
    required this.status,
    required this.instructions,
    this.orderId,
    required this.createdAt,
  });

  factory Payment.fromJson(Map<String, dynamic> json) {
    return Payment(
      id: json['payment_id'] ?? json['id'] ?? '',
      amount: (json['amount'] ?? 0).toDouble(),
      userMethod: json['user_method'] ?? json['userMethod'] ?? 'mpesa',
      status: json['status'] ?? 'pending',
      instructions: json['instructions'] ?? '',
      orderId: json['order_id'] ?? json['orderId'],
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'payment_id': id,
      'amount': amount,
      'user_method': userMethod,
      'status': status,
      'instructions': instructions,
      'order_id': orderId,
      'created_at': createdAt.toIso8601String(),
    };
  }

  bool get isPending => status == 'pending';
  bool get isPaid => status == 'paid';
  bool get isFailed => status == 'failed';

  bool get isQrCode => instructions.startsWith('QR:');
  bool get isUssd => instructions.startsWith('USSD:');

  String? get qrCodeData {
    if (isQrCode) {
      return instructions.substring(3); // Remove "QR:" prefix
    }
    return null;
  }

  String? get ussdCode {
    if (isUssd) {
      return instructions.substring(5); // Remove "USSD:" prefix
    }
    return null;
  }
}





