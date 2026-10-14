import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/theme/app_colors.dart';
import '../../services/social_review_service.dart';
import '../../shared/utils/compact_number.dart';

class ReviewThreadPage extends StatefulWidget {
  final String reviewType;
  final String reviewId;

  const ReviewThreadPage({
    super.key,
    required this.reviewType,
    required this.reviewId,
  });

  @override
  State<ReviewThreadPage> createState() => _ReviewThreadPageState();
}

class _ReviewThreadPageState extends State<ReviewThreadPage> {
  final SocialReviewService _service = SocialReviewService();
  final TextEditingController _replyController = TextEditingController();
  Map<String, dynamic>? _review;
  List<Map<String, dynamic>> _replies = const [];
  bool _loading = true;
  bool _sending = false;
  bool _liked = false;
  int _likes = 0;
  Map<String, dynamic>? _replyingTo;
  RealtimeChannel? _threadChannel;

  @override
  void initState() {
    super.initState();
    _load();
    _subscribe();
  }

  @override
  void dispose() {
    _threadChannel?.unsubscribe();
    _replyController.dispose();
    super.dispose();
  }

  void _subscribe() {
    _threadChannel = Supabase.instance.client
        .channel('review-thread-${widget.reviewType}-${widget.reviewId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'social_review_replies',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'review_id',
            value: widget.reviewId,
          ),
          callback: (_) => _load(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: widget.reviewType == 'courier'
              ? 'courier_review_likes'
              : 'menu_item_review_likes',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'review_id',
            value: widget.reviewId,
          ),
          callback: (_) => _load(),
        )
        .subscribe();
  }

  Future<void> _load() async {
    final reviewFuture = _service.getReview(widget.reviewType, widget.reviewId);
    final repliesFuture = _service.getReplies(
      widget.reviewType,
      widget.reviewId,
    );
    final likeStateFuture = _service.getReviewLikeState(
      widget.reviewType,
      widget.reviewId,
    );
    Map<String, dynamic>? review;
    List<Map<String, dynamic>> replies = const [];
    Map<String, dynamic> likeState = const {};
    try {
      review = await reviewFuture;
    } catch (_) {}
    try {
      replies = await repliesFuture;
    } catch (_) {}
    try {
      likeState = await likeStateFuture;
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _review = review;
      _replies = replies;
      _likes = (likeState['count'] as num?)?.toInt() ?? 0;
      _liked = likeState['liked'] == true;
      _loading = false;
    });
  }

  Future<void> _sendReply() async {
    final body = _replyController.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _service.addReply(
        widget.reviewType,
        widget.reviewId,
        body,
        parentReplyId: _replyingTo?['id']?.toString(),
      );
      _replyController.clear();
      if (mounted) setState(() => _replyingTo = null);
      await _load();
    } catch (_) {
      _show('Nao foi possivel publicar a resposta.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _show(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _report(String type, String id) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Denunciar conteudo'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'Explique o problema'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason == null || reason.length < 3) return;
    try {
      await _service.report(type, id, reason);
      _show('Denuncia enviada para analise.');
    } catch (_) {
      _show('Nao foi possivel enviar a denuncia.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final review = _review;
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      appBar: AppBar(
        title: const Text('Comentario'),
        actions: [
          if (review != null)
            PopupMenuButton<String>(
              onSelected: (value) async {
                if (value == 'report') {
                  await _report(widget.reviewType, widget.reviewId);
                }
                if (value == 'pin') {
                  try {
                    await _service.setPinned(
                      widget.reviewType,
                      widget.reviewId,
                      review['is_pinned'] != true,
                    );
                    await _load();
                  } catch (_) {
                    _show('Apenas o responsavel pode fixar este comentario.');
                  }
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'pin',
                  child: Text(
                    review['is_pinned'] == true
                        ? 'Desafixar comentario'
                        : 'Fixar comentario',
                  ),
                ),
                const PopupMenuItem(
                  value: 'report',
                  child: Text('Denunciar comentario'),
                ),
              ],
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : review == null
          ? const Center(child: Text('Comentario nao encontrado.'))
          : Column(
              children: [
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _ReviewCard(
                          review: review,
                          likes: _likes,
                          liked: _liked,
                          onLike: () async {
                            try {
                              await _service.toggleReviewLike(
                                widget.reviewType,
                                widget.reviewId,
                              );
                              await _load();
                            } catch (_) {
                              _show(
                                'Nao foi possivel curtir este comentario agora.',
                              );
                            }
                          },
                        ),
                        const SizedBox(height: 18),
                        Text(
                          '${_replies.length} respostas',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 10),
                        ..._replies.map(
                          (reply) => Padding(
                            padding: EdgeInsets.only(
                              left: reply['parent_reply_id'] == null ? 0 : 20,
                            ),
                            child: _ReplyCard(
                              reply: reply,
                              onLike: () async {
                                try {
                                  await _service.toggleReplyLike(
                                    reply['id'].toString(),
                                  );
                                  await _load();
                                } catch (_) {
                                  _show(
                                    'Nao foi possivel curtir esta resposta agora.',
                                  );
                                }
                              },
                              onReport: () =>
                                  _report('reply', reply['id'].toString()),
                              onReply: () {
                                setState(() {
                                  _replyingTo = reply;
                                  _replyController.text =
                                      '@${reply['author_name'] ?? 'Utilizador'} ';
                                  _replyController.selection =
                                      TextSelection.fromPosition(
                                        TextPosition(
                                          offset: _replyController.text.length,
                                        ),
                                      );
                                });
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (Supabase.instance.client.auth.currentUser != null)
                  SafeArea(
                    top: false,
                    child: Container(
                      color: Colors.white,
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      child: Column(
                        children: [
                          if (_replyingTo != null)
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'A responder a ${_replyingTo!['author_name'] ?? 'Utilizador'}',
                                    style: const TextStyle(
                                      color: Colors.black54,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Cancelar resposta',
                                  onPressed: () => setState(() {
                                    _replyingTo = null;
                                    _replyController.clear();
                                  }),
                                  icon: const Icon(Icons.close, size: 18),
                                ),
                              ],
                            ),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _replyController,
                                  minLines: 1,
                                  maxLines: 4,
                                  decoration: const InputDecoration(
                                    hintText: 'Escreva uma resposta...',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton.filled(
                                onPressed: _sending ? null : _sendReply,
                                tooltip: 'Publicar resposta',
                                icon: _sending
                                    ? const SizedBox.square(
                                        dimension: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.send_rounded),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final Map<String, dynamic> review;
  final int likes;
  final bool liked;
  final VoidCallback onLike;
  const _ReviewCard({
    required this.review,
    required this.likes,
    required this.liked,
    required this.onLike,
  });

  @override
  Widget build(BuildContext context) {
    final item = (review['menu_items'] as Map?)?.cast<String, dynamic>();
    final title = item?['name']?.toString() ?? 'Avaliacao do estafeta';
    final image =
        review['image_url']?.toString() ?? item?['image_url']?.toString();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE8E8E8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: AppColors.primaryRed.withValues(alpha: .12),
                child: const Icon(Icons.person, color: AppColors.primaryRed),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      review['reviewer_name']?.toString() ?? 'Cliente DeliGo',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (review['is_pinned'] == true)
                const Icon(
                  Icons.push_pin_rounded,
                  color: AppColors.primaryRed,
                  size: 20,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: List.generate(
              5,
              (index) => Icon(
                index < ((review['rating'] as num?)?.toInt() ?? 0)
                    ? Icons.star_rounded
                    : Icons.star_border_rounded,
                color: const Color(0xFFFFB000),
                size: 20,
              ),
            ),
          ),
          if ((review['comment']?.toString().trim() ?? '').isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              review['comment'].toString(),
              style: const TextStyle(fontSize: 15, height: 1.4),
            ),
          ],
          if (image != null && image.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedNetworkImage(
                imageUrl: image,
                height: 190,
                width: double.infinity,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ],
          const Divider(height: 28),
          TextButton.icon(
            onPressed: onLike,
            icon: Icon(
              liked ? Icons.thumb_up_alt_rounded : Icons.thumb_up_alt_outlined,
              color: liked ? AppColors.primaryRed : Colors.black54,
            ),
            label: Text('${formatCompactNumber(likes)} gostos'),
          ),
        ],
      ),
    );
  }
}

class _ReplyCard extends StatelessWidget {
  final Map<String, dynamic> reply;
  final VoidCallback onLike;
  final VoidCallback onReport;
  final VoidCallback onReply;
  const _ReplyCard({
    required this.reply,
    required this.onLike,
    required this.onReport,
    required this.onReply,
  });

  @override
  Widget build(BuildContext context) {
    final official = const [
      'restaurant',
      'courier',
      'admin',
    ].contains(reply['author_role']?.toString());
    final liked = reply['liked_by_me'] == true;
    final count = (reply['likes_count'] as num?)?.toInt() ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: official
                ? AppColors.primaryRed
                : const Color(0xFFEDEDED),
            child: Icon(
              official ? Icons.storefront : Icons.person,
              size: 18,
              color: official ? Colors.white : Colors.black54,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          reply['author_name']?.toString() ?? 'Utilizador',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      if (official)
                        const Text(
                          'OFICIAL',
                          style: TextStyle(
                            color: AppColors.primaryRed,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(reply['body']?.toString() ?? ''),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: onLike,
                        icon: Icon(
                          liked
                              ? Icons.thumb_up_alt_rounded
                              : Icons.thumb_up_alt_outlined,
                          size: 16,
                        ),
                        label: Text(count == 0 ? 'Gostar' : '$count'),
                      ),
                      TextButton.icon(
                        onPressed: onReply,
                        icon: const Icon(Icons.reply_rounded, size: 16),
                        label: const Text('Responder'),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: onReport,
                        tooltip: 'Denunciar',
                        icon: const Icon(Icons.flag_outlined, size: 18),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
