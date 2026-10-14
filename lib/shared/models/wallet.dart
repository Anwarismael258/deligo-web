class Wallet {
  final int id;
  final String name;
  final String owner;
  final double balance;
  final String type; // 'mpesa' ou 'emola'

  Wallet({
    required this.id,
    required this.name,
    required this.owner,
    required this.balance,
    required this.type,
  });

  Wallet copyWith({
    int? id,
    String? name,
    String? owner,
    double? balance,
    String? type,
  }) {
    return Wallet(
      id: id ?? this.id,
      name: name ?? this.name,
      owner: owner ?? this.owner,
      balance: balance ?? this.balance,
      type: type ?? this.type,
    );
  }

  factory Wallet.fromMap(Map<String, dynamic> map) {
    return Wallet(
      id: map['id'] as int,
      name: map['name'] as String,
      owner: map['owner'] as String,
      balance: (map['balance'] as num?)?.toDouble() ?? 0.0,
      type: map['type'] as String? ?? 'mpesa',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'owner': owner,
      'balance': balance,
      'type': type,
    };
  }
}

