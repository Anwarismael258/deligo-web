class MenuItemReview {
  final String id;
  final String menuItemId;
  final String? menuItemName;
  final String reviewerId;
  final String reviewerName;
  final String? reviewerAvatarUrl;
  final int rating;
  final String? comment;
  final String? imageUrl;
  final int likesCount;
  final bool likedByCurrentUser;
  final bool isVerifiedReviewer;
  final DateTime createdAt;

  const MenuItemReview({
    required this.id,
    required this.menuItemId,
    this.menuItemName,
    required this.reviewerId,
    required this.reviewerName,
    this.reviewerAvatarUrl,
    required this.rating,
    this.comment,
    this.imageUrl,
    this.likesCount = 0,
    this.likedByCurrentUser = false,
    this.isVerifiedReviewer = false,
    required this.createdAt,
  });

  factory MenuItemReview.fromMap(Map<String, dynamic> map) {
    final rawCreatedAt = map['created_at']?.toString();
    return MenuItemReview(
      id: map['id']?.toString() ?? '',
      menuItemId: map['menu_item_id']?.toString() ?? '',
      menuItemName: map['menu_item_name']?.toString(),
      reviewerId: map['reviewer_id']?.toString() ?? '',
      reviewerName: map['reviewer_name']?.toString().trim().isNotEmpty == true
          ? map['reviewer_name'].toString()
          : 'Cliente',
      reviewerAvatarUrl: map['reviewer_avatar_url']?.toString(),
      rating: (map['rating'] as num?)?.toInt() ?? 5,
      comment: map['comment']?.toString(),
      imageUrl: map['image_url']?.toString(),
      likesCount: (map['likes_count'] as num?)?.toInt() ?? 0,
      likedByCurrentUser: map['liked_by_current_user'] == true,
      isVerifiedReviewer: map['reviewer_verified'] == true,
      createdAt: rawCreatedAt != null
          ? (DateTime.tryParse(rawCreatedAt) ?? DateTime.now())
          : DateTime.now(),
    );
  }
}
