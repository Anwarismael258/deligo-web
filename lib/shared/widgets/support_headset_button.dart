import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupportHeadsetButton extends StatefulWidget {
  const SupportHeadsetButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<SupportHeadsetButton> createState() => _SupportHeadsetButtonState();
}

class _SupportHeadsetButtonState extends State<SupportHeadsetButton>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  RealtimeChannel? _channel;
  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
    lowerBound: 0.92,
    upperBound: 1.08,
  );
  int _unreadCount = 0;
  String? _userId;

  @override
  void initState() {
    super.initState();
    unawaited(_loadAndSubscribe());
  }

  Future<void> _loadAndSubscribe() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) return;
    _userId = userId;
    await _loadCount();
    if (!mounted) return;
    _channel =
        _supabase
            .channel('support-unread-badge-$userId')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'push_notifications',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'user_id',
                value: userId,
              ),
              callback: (_) => unawaited(_loadCount()),
            )
          ..subscribe();
  }

  Future<void> _loadCount() async {
    final userId = _userId ?? _supabase.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) return;
    try {
      final rows = await _supabase
          .from('push_notifications')
          .select('id')
          .eq('user_id', userId)
          .eq('type', 'SUPPORT_MESSAGE_RECEIVED')
          .isFilter('read_at', null);
      final next = (rows as List).length;
      if (!mounted) return;
      final increased = next > _unreadCount;
      setState(() => _unreadCount = next);
      if (increased) {
        _pulseController
          ..stop()
          ..repeat(reverse: true);
        Future<void>.delayed(const Duration(seconds: 4), () {
          if (mounted) _pulseController.stop();
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    unawaited(_channel?.unsubscribe());
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = _unreadCount;
    return ScaleTransition(
      scale: _pulseController,
      child: IconButton(
        tooltip: 'Central de suporte',
        onPressed: widget.onPressed,
        icon: Badge(
          isLabelVisible: count > 0,
          backgroundColor: Colors.red,
          label: Text(count > 99 ? '99+' : '$count'),
          child: const Icon(Icons.headset_mic_outlined),
        ),
      ),
    );
  }
}
