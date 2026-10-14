class Restaurant {
  final String id;
  final String ownerId;
  final String name;
  final String? description;
  final String? phone;
  final String address;
  final double? latitude;
  final double? longitude;
  final String? neighborhood;
  final String? city;
  final bool isOpen;
  final DateTime createdAt;

  // Dados adicionais calculados
  final double? distance;
  final double? rating;
  final int? deliveryFee;
  final int? deliveryTime; // em minutos
  final String? imageUrl;
  final bool freeDelivery;

  Restaurant({
    required this.id,
    required this.ownerId,
    required this.name,
    this.description,
    this.phone,
    required this.address,
    this.latitude,
    this.longitude,
    this.neighborhood,
    this.city,
    this.isOpen = true,
    required this.createdAt,
    this.distance,
    this.rating,
    this.deliveryFee,
    this.deliveryTime,
    this.imageUrl,
    this.freeDelivery = false,
  });

  factory Restaurant.fromMap(Map<String, dynamic> map) {
    DateTime createdAt;
    final rawCreatedAt = map['created_at'];
    if (rawCreatedAt is String) {
      createdAt = DateTime.tryParse(rawCreatedAt) ?? DateTime.now();
    } else {
      createdAt = DateTime.now();
    }

    final rawIsOpen = map['is_open'];
    bool isOpen = true;
    if (rawIsOpen is bool) {
      isOpen = rawIsOpen;
    } else if (rawIsOpen is num) {
      isOpen = rawIsOpen != 0;
    } else if (rawIsOpen is String) {
      final normalized = rawIsOpen.trim().toLowerCase();
      isOpen = normalized == 'true' || normalized == '1';
    }

    return Restaurant(
      id: map['id']?.toString() ?? '',
      ownerId: map['owner_id']?.toString() ?? '',
      name: map['name']?.toString() ?? 'Restaurante',
      description: map['description'] as String?,
      phone: map['phone'] as String?,
      address: map['address']?.toString() ?? 'Endereco indisponivel',
      latitude: map['latitude'] != null
          ? double.tryParse(map['latitude'].toString())
          : null,
      longitude: map['longitude'] != null
          ? double.tryParse(map['longitude'].toString())
          : null,
      neighborhood: map['neighborhood'] as String?,
      city: map['city'] as String?,
      isOpen: isOpen,
      createdAt: createdAt,
      distance: map['distance'] == null
          ? null
          : double.tryParse(map['distance'].toString()),
      rating: map['rating'] == null
          ? null
          : double.tryParse(map['rating'].toString()),
      deliveryFee: map['delivery_fee'] == null
          ? null
          : int.tryParse(map['delivery_fee'].toString()),
      deliveryTime: map['delivery_time'] == null
          ? null
          : int.tryParse(map['delivery_time'].toString()),
      imageUrl: map['image_url']?.toString(),
      freeDelivery:
          map['free_delivery'] == true ||
          ((map['delivery_fee'] as num?)?.toDouble() ?? 1) <= 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'owner_id': ownerId,
      'name': name,
      'description': description,
      'phone': phone,
      'address': address,
      'latitude': latitude,
      'longitude': longitude,
      'neighborhood': neighborhood,
      'city': city,
      'is_open': isOpen,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
