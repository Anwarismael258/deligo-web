import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/chat_notification_utils.dart';

class OrderChatButton extends StatefulWidget {
  final String orderId;
  final VoidCallback? onPressed;
  final String label;
  final int? unreadCount;
  final bool showCountInLabel;
  final ButtonStyle? style;
  final Color? iconColor;

  const OrderChatButton({
    super.key,
    required this.orderId,
    required this.onPressed,
    this.label = 'Abrir chat',
    this.unreadCount,
    this.showCountInLabel = true,
    this.style,
    this.iconColor,
  });

  @override
  State<OrderChatButton> createState() => _OrderChatButtonState();
}

class _OrderChatButtonState extends State<OrderChatButton> {
  final SupabaseClient _supabase = Supabase.instance.client;
  RealtimeChannel? _notificationsChannel;
  String? _channelUserId;
  int _liveUnreadCount = 0;

  int get _effectiveUnreadCount => widget.unreadCount ?? _liveUnreadCount;
  bool get _usesProvidedCount => widget.unreadCount != null;

  @override
  void initState() {
    super.initState();
    unawaited(_configureUnreadSync());
  }

  @override
  void didUpdateWidget(covariant OrderChatButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    final orderChanged = oldWidget.orderId != widget.orderId;
    final sourceChanged =
        (oldWidget.unreadCount != null) != (widget.unreadCount != null);
    if (orderChanged || sourceChanged) {
      unawaited(_configureUnreadSync());
    }
  }

  Future<void> _configureUnreadSync() async {
    if (_usesProvidedCount) {
      await _unsubscribeRealtime();
      if (mounted) {
        setState(() => _liveUnreadCount = 0);
      }
      return;
    }

    await _ensureRealtimeSubscription();
    await _loadUnreadCount();
  }

  Future<void> _ensureRealtimeSubscription() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) {
      await _unsubscribeRealtime();
      return;
    }
    if (_channelUserId == userId && _notificationsChannel != null) return;

    await _unsubscribeRealtime();
    _channelUserId = userId;
    _notificationsChannel = _supabase.channel(
      'order-chat-button-$userId-${widget.orderId}-${identityHashCode(this)}',
    );
    _notificationsChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'push_notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) {
            final row = Map<String, dynamic>.from(
              payload.newRecord.isNotEmpty
                  ? payload.newRecord
                  : payload.oldRecord,
            );
            if (!_matchesCurrentOrder(row)) return;
            unawaited(_loadUnreadCount());
          },
        )
        .subscribe();
  }

  Future<void> _loadUnreadCount() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) return;

    try {
      final response = await _supabase
          .from('push_notifications')
          .select('entity_id, metadata, data, type, read_at')
          .eq('user_id', userId)
          .eq('type', 'MESSAGE_RECEIVED')
          .isFilter('read_at', null);

      final count = (response as List)
          .cast<Map<String, dynamic>>()
          .where(_matchesCurrentOrder)
          .length;

      if (!mounted) return;
      setState(() => _liveUnreadCount = count);
    } catch (_) {}
  }

  bool _matchesCurrentOrder(Map<String, dynamic> notification) {
    return ChatNotificationUtils.matchesOrder(notification, widget.orderId);
  }

  Future<void> _unsubscribeRealtime() async {
    await _notificationsChannel?.unsubscribe();
    _notificationsChannel = null;
    _channelUserId = null;
  }

  @override
  void dispose() {
    unawaited(_unsubscribeRealtime());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final unreadCount = _effectiveUnreadCount;
    final buttonLabel = widget.showCountInLabel && unreadCount > 0
        ? '${widget.label} ($unreadCount)'
        : widget.label;

    return OutlinedButton.icon(
      onPressed: widget.onPressed,
      style: widget.style,
      icon: Badge(
        isLabelVisible: unreadCount > 0,
        backgroundColor: Colors.redAccent,
        label: Text(unreadCount > 99 ? '99+' : unreadCount.toString()),
        child: Icon(
          Icons.chat_bubble_outline,
          color: widget.iconColor,
        ),
      ),
      label: Text(buttonLabel),
    );
  }
}
