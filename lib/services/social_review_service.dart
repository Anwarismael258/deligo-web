import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SocialReviewService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<Map<String, dynamic>?> getReview(String type, String id) async {
    final reviewId = id.trim();
    if (reviewId.isEmpty) return null;
    if (type == 'courier') {
      final row = await _supabase
          .from('courier_reviews')
          .select(
            'id, courier_id, reviewer_id, reviewer_name, rating, comment, created_at, is_pinned',
          )
          .eq('id', reviewId)
          .limit(1)
          .maybeSingle();
      return row == null ? null : Map<String, dynamic>.from(row);
    }
    // Keep the review lookup independent from optional foreign-key
    // relationships. A missing relationship must not turn a real review into
    // the misleading "Comentario nao encontrado" state.
    final row = await _supabase
        .from('menu_item_reviews')
        .select(
          'id, menu_item_id, reviewer_id, reviewer_name, rating, comment, image_url, created_at, is_pinned',
        )
        .eq('id', reviewId)
        .limit(1)
        .maybeSingle();
    if (row == null) return null;
    final result = Map<String, dynamic>.from(row);
    final menuItemId = result['menu_item_id']?.toString() ?? '';
    if (menuItemId.isNotEmpty) {
      try {
        final item = await _supabase
            .from('menu_items')
            .select('name, image_url, restaurant_id')
            .eq('id', menuItemId)
            .maybeSingle();
        if (item != null) result['menu_items'] = item;
      } catch (_) {
        // The review itself remains valid even if catalog enrichment fails.
      }
    }
    return result;
  }

  Future<List<Map<String, dynamic>>> getReplies(String type, String id) async {
    final rows = await _supabase
        .from('social_review_replies')
        .select('*')
        .eq('review_type', type)
        .eq('review_id', id)
        .order('created_at');
    final replies = (rows as List).cast<Map<String, dynamic>>();
    final ids = replies
        .map((row) => row['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();
    if (ids.isEmpty) return replies;
    final likes = await _supabase
        .from('social_review_reply_likes')
        .select('reply_id, user_id')
        .inFilter('reply_id', ids);
    final counts = <String, int>{};
    final mine = <String>{};
    final userId = _supabase.auth.currentUser?.id;
    for (final like in (likes as List).cast<Map<String, dynamic>>()) {
      final replyId = like['reply_id']?.toString() ?? '';
      counts[replyId] = (counts[replyId] ?? 0) + 1;
      if (like['user_id']?.toString() == userId) mine.add(replyId);
    }
    return replies.map((row) {
      final replyId = row['id']?.toString() ?? '';
      return {
        ...row,
        'likes_count': counts[replyId] ?? 0,
        'liked_by_me': mine.contains(replyId),
      };
    }).toList();
  }

  Future<void> addReply(
    String type,
    String id,
    String body, {
    String? parentReplyId,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw StateError('login_required');
    Map<String, dynamic>? profile;
    try {
      profile = await _supabase
          .from('profiles')
          .select('full_name, role')
          .eq('id', user.id)
          .maybeSingle();
    } catch (error) {
      // A profile is optional for publishing; do not block a valid reply when
      // the profile row is unavailable.
      profile = null;
      // Keep the diagnostic for the real insert error below readable.
      debugPrint('SocialReviewService profile lookup: $error');
    }
    final normalizedType = type == 'courier' ? 'courier' : 'menu_item';
    final normalizedParent = parentReplyId?.trim();
    final payload = <String, dynamic>{
      'review_type': normalizedType,
      'review_id': id,
      'author_id': user.id,
      'author_name': profile?['full_name']?.toString().trim().isNotEmpty == true
          ? profile!['full_name']
          : profile?['name']?.toString().trim().isNotEmpty == true
          ? profile!['name']
          : 'Utilizador DeliGo',
      'author_role': profile?['role'] ?? 'client',
      'body': body.trim(),
    };
    if (normalizedParent != null && normalizedParent.isNotEmpty) {
      payload['parent_reply_id'] = normalizedParent;
    }
    try {
      await _supabase.from('social_review_replies').insert(payload);
    } catch (error) {
      // Keep the same replies system, but retry with only the canonical
      // columns. This protects publishing when an older database schema does
      // not yet expose optional author metadata columns.
      debugPrint('SocialReviewService full reply insert failed: $error');
      final minimalPayload = <String, dynamic>{
        'review_type': normalizedType,
        'review_id': id,
        'author_id': user.id,
        'body': body.trim(),
        if (normalizedParent != null && normalizedParent.isNotEmpty)
          'parent_reply_id': normalizedParent,
      };
      await _supabase.from('social_review_replies').insert(minimalPayload);
    }
  }

  Future<void> toggleReviewLike(String type, String id) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw StateError('login_required');
    final table = type == 'courier'
        ? 'courier_review_likes'
        : 'menu_item_review_likes';
    final existing = await _supabase
        .from(table)
        .select('review_id')
        .eq('review_id', id)
        .eq('user_id', userId)
        .maybeSingle();
    if (existing == null) {
      await _supabase.from(table).insert({'review_id': id, 'user_id': userId});
    } else {
      await _supabase
          .from(table)
          .delete()
          .eq('review_id', id)
          .eq('user_id', userId);
    }
  }

  Future<Map<String, dynamic>> getReviewLikeState(
    String type,
    String id,
  ) async {
    final table = type == 'courier'
        ? 'courier_review_likes'
        : 'menu_item_review_likes';
    final rows = await _supabase
        .from(table)
        .select('user_id')
        .eq('review_id', id);
    final likes = (rows as List).cast<Map<String, dynamic>>();
    final userId = _supabase.auth.currentUser?.id;
    return {
      'count': likes.length,
      'liked': likes.any((row) => row['user_id']?.toString() == userId),
    };
  }

  Future<void> toggleReplyLike(String replyId) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw StateError('login_required');
    final existing = await _supabase
        .from('social_review_reply_likes')
        .select('reply_id')
        .eq('reply_id', replyId)
        .eq('user_id', userId)
        .maybeSingle();
    if (existing == null) {
      await _supabase.from('social_review_reply_likes').insert({
        'reply_id': replyId,
        'user_id': userId,
      });
    } else {
      await _supabase
          .from('social_review_reply_likes')
          .delete()
          .eq('reply_id', replyId)
          .eq('user_id', userId);
    }
  }

  Future<void> setPinned(String type, String id, bool pinned) => _supabase.rpc(
    'set_social_review_pinned',
    params: {'p_review_type': type, 'p_review_id': id, 'p_pinned': pinned},
  );

  Future<void> report(String type, String id, String reason) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw StateError('login_required');
    await _supabase.from('social_review_reports').upsert({
      'review_type': type,
      'review_id': id,
      'reporter_id': userId,
      'reason': reason.trim(),
      'status': 'open',
    }, onConflict: 'review_type,review_id,reporter_id');
  }
}
