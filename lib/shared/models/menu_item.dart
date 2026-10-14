class MenuItem {
  final String id;
  final String restaurantId;
  final String name;
  final String? description;
  final double price;
  final String? imageUrl;
  final List<String> imageUrls;
  final String? category;
  final bool isAvailable;
  final int stockQuantity;
  final double rating;
  final int prepTimeMinutes;
  final DateTime createdAt;

  MenuItem({
    required this.id,
    required this.restaurantId,
    required this.name,
    this.description,
    required this.price,
    this.imageUrl,
    this.imageUrls = const [],
    this.category,
    this.isAvailable = true,
    this.stockQuantity = 0,
    this.rating = 0,
    this.prepTimeMinutes = 25,
    required this.createdAt,
  });

  factory MenuItem.fromMap(Map<String, dynamic> map) {
    final createdAtRaw = map['created_at']?.toString();
    final createdAt = createdAtRaw != null && createdAtRaw.isNotEmpty
        ? DateTime.tryParse(createdAtRaw)
        : null;
    final isAvailableRaw = map['is_available'];
    final isAvailable = isAvailableRaw is bool
        ? isAvailableRaw
        : (isAvailableRaw is num
              ? isAvailableRaw != 0
              : (isAvailableRaw?.toString().toLowerCase() != 'false'));

    final rawGallery = map['image_urls'];
    final gallery = rawGallery is List
        ? rawGallery
              .map((value) => value.toString().trim())
              .where((value) => value.isNotEmpty)
              .toList()
        : <String>[];
    final primary = map['image_url']?.toString().trim();
    if (primary != null && primary.isNotEmpty && !gallery.contains(primary)) {
      gallery.insert(0, primary);
    }
    return MenuItem(
      id: map['id']?.toString() ?? '',
      restaurantId: map['restaurant_id']?.toString() ?? '',
      name: map['name']?.toString() ?? 'Prato',
      description: map['description'] as String?,
      price: double.tryParse(map['price'].toString()) ?? 0.0,
      imageUrl: primary,
      imageUrls: gallery,
      category: map['category'] as String?,
      isAvailable: isAvailable,
      stockQuantity: (map['stock_quantity'] as num?)?.toInt() ?? 0,
      rating:
          double.tryParse(
            (map['item_rating'] ?? map['rating'] ?? 0).toString(),
          ) ??
          0,
      prepTimeMinutes: (map['prep_time_minutes'] as num?)?.toInt() ?? 25,
      createdAt: createdAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'restaurant_id': restaurantId,
      'name': name,
      'description': description,
      'price': price,
      'image_url': imageUrl,
      'image_urls': imageUrls,
      'category': category,
      'is_available': isAvailable,
      'stock_quantity': stockQuantity,
      'item_rating': rating,
      'prep_time_minutes': prepTimeMinutes,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
