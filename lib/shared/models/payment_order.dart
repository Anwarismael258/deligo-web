class PaymentOrder {
  final String id;
  final double totalAmount;
  final String description;
  final String customerName;
  final String customerPhone;
  final String customerEmail;
  final String? walletId;

  PaymentOrder({
    required this.id,
    required this.totalAmount,
    required this.description,
    required this.customerName,
    required this.customerPhone,
    required this.customerEmail,
    this.walletId,
  });

  factory PaymentOrder.fromMap(Map<String, dynamic> map) {
    return PaymentOrder(
      id: map['id'] ?? '',
      totalAmount: (map['total_amount'] ?? 0).toDouble(),
      description: map['description'] ?? 'Pagamento Deligo',
      customerName: map['customer_name'] ?? '',
      customerPhone: map['customer_phone'] ?? '',
      customerEmail: map['customer_email'] ?? '',
      walletId: map['wallet_id']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'total_amount': totalAmount,
      'description': description,
      'customer_name': customerName,
      'customer_phone': customerPhone,
      'customer_email': customerEmail,
      'wallet_id': walletId,
    };
  }
}





