import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/theme/app_colors.dart';
import '../../services/notification_dispatch_service.dart';
import '../../services/push_notification_service.dart';

class SupportChatPage extends StatefulWidget {
  final String title;
  final String role;
  final String? ticketId;

  const SupportChatPage({
    super.key,
    required this.title,
    required this.role,
    this.ticketId,
  });

  @override
  State<SupportChatPage> createState() => _SupportChatPageState();
}

class _SupportChatMessage {
  const _SupportChatMessage({
    required this.id,
    required this.ticketId,
    required this.senderId,
    required this.senderName,
    required this.senderRole,
    required this.text,
    required this.createdAt,
    this.readAt,
  });

  final String id;
  final String ticketId;
  final String senderId;
  final String senderName;
  final String senderRole;
  final String text;
  final DateTime createdAt;
  final DateTime? readAt;

  factory _SupportChatMessage.fromMap(Map<String, dynamic> map) {
    return _SupportChatMessage(
      id: map['id']?.toString() ?? '',
      ticketId: map['ticket_id']?.toString() ?? '',
      senderId: map['sender_id']?.toString() ?? '',
      senderName: map['sender_name']?.toString() ?? '',
      senderRole: map['sender_role']?.toString() ?? 'client',
      text: map['text']?.toString() ?? '',
      createdAt:
          DateTime.tryParse(map['created_at']?.toString() ?? '') ??
          DateTime.now(),
      readAt: DateTime.tryParse(map['read_at']?.toString() ?? ''),
    );
  }
}

class _SupportChatPageState extends State<SupportChatPage> {
  final _supabase = Supabase.instance.client;
  final _messageController = TextEditingController();
  final _ticketSearchController = TextEditingController();
  final _scrollController = ScrollController();
  final _ticketListController = ScrollController();

  RealtimeChannel? _messagesChannel;
  RealtimeChannel? _ticketsChannel;
  RealtimeChannel? _staffMessagesChannel;
  bool _loading = true;
  bool _sending = false;
  String _ticketId = '';
  String _userRole = 'client';
  String _userName = 'Usuario';
  String _userPhone = '';
  String _userEmail = '';
  Map<String, dynamic> _ticket = const {};
  List<_SupportChatMessage> _messages = const [];
  List<Map<String, dynamic>> _staffTickets = const [];
  final Set<String> _signalledMessageIds = <String>{};
  String _ticketQuery = '';

  bool get _isStaff => _userRole == 'support_agent' || _userRole == 'admin';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _messagesChannel?.unsubscribe();
    _ticketsChannel?.unsubscribe();
    _staffMessagesChannel?.unsubscribe();
    _messageController.dispose();
    _ticketSearchController.dispose();
    _scrollController.dispose();
    _ticketListController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      await _loadUser();
      if (widget.ticketId?.trim().isNotEmpty == true) {
        _ticketId = widget.ticketId!.trim();
      } else if (_isStaff) {
        _staffTickets = await _loadStaffTickets();
        _ticketId = await _loadNextOpenTicket();
        _subscribeToTicketQueue();
        _subscribeToStaffMessages();
      } else {
        _ticketId = await _ensureClientTicket();
      }

      if (_ticketId.isNotEmpty) {
        await _loadTicket();
        await _loadMessages();
        await _subscribeToMessages();
        await _markRead();
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadUser() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    final profile = await _supabase
        .from('profiles')
        .select('full_name, role, phone, email')
        .eq('id', user.id)
        .maybeSingle();
    final fetchedName = profile?['full_name']?.toString().trim() ?? '';
    _userName = fetchedName.isNotEmpty ? fetchedName : 'Usuario';
    _userRole = profile?['role']?.toString() ?? widget.role;
    _userPhone = profile?['phone']?.toString().trim() ?? '';
    _userEmail = profile?['email']?.toString().trim() ?? user.email ?? '';
  }

  Future<String> _ensureClientTicket() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return '';

    final existing = await _supabase
        .from('support_tickets')
        .select('id')
        .eq('opened_by', user.id)
        .inFilter('status', ['open', 'in_progress'])
        .order('updated_at', ascending: false)
        .limit(1)
        .maybeSingle();
    final existingId = existing?['id']?.toString() ?? '';
    if (existingId.isNotEmpty) return existingId;

    final inserted = await _supabase
        .from('support_tickets')
        .insert({
          'external_source': 'deligo_chat',
          'opened_by': user.id,
          'opened_by_role': _userRole,
          'customer_name': _userName,
          if (_userPhone.isNotEmpty) 'customer_phone': _userPhone,
          if (_userEmail.isNotEmpty) 'customer_email': _userEmail,
          'dispute_type': 'support_chat',
          'reason': 'Chat de suporte DeliGo',
          'status': 'open',
        })
        .select('id')
        .single();
    return inserted['id']?.toString() ?? '';
  }

  Future<String> _loadNextOpenTicket() async {
    if (_staffTickets.isNotEmpty) {
      return _staffTickets.first['id']?.toString() ?? '';
    }
    final existing = await _supabase
        .from('support_tickets')
        .select('id')
        .inFilter('status', ['open', 'in_progress'])
        .order('updated_at', ascending: false)
        .limit(1)
        .maybeSingle();
    return existing?['id']?.toString() ?? '';
  }

  Future<List<Map<String, dynamic>>> _loadStaffTickets() async {
    final response = await _supabase
        .from('support_tickets')
        .select(
          'id, opened_by, opened_by_role, customer_name, customer_phone, '
          'customer_email, reason, status, assigned_to, created_at, updated_at',
        )
        .inFilter('status', ['open', 'in_progress'])
        .order('updated_at', ascending: false)
        .limit(120);
    return (response as List)
        .cast<Map<String, dynamic>>()
        .map(Map<String, dynamic>.from)
        .toList();
  }

  void _subscribeToTicketQueue() {
    if (!_isStaff || _ticketsChannel != null) return;
    _ticketsChannel = _supabase
        .channel(
          'support-ticket-queue-${_supabase.auth.currentUser?.id ?? 'staff'}',
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'support_tickets',
          callback: (_) async {
            final tickets = await _loadStaffTickets();
            await _applyRealtimeStaffTickets(tickets);
          },
        )
        .subscribe();
  }

  void _subscribeToStaffMessages() {
    if (!_isStaff || _staffMessagesChannel != null) return;
    _staffMessagesChannel = _supabase
        .channel(
          'support-message-signal-${_supabase.auth.currentUser?.id ?? 'staff'}',
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'support_messages',
          callback: (payload) async {
            if (payload.newRecord.isEmpty) return;
            final message = _SupportChatMessage.fromMap(
              Map<String, dynamic>.from(payload.newRecord),
            );
            if (message.senderId == _supabase.auth.currentUser?.id) return;
            final tickets = await _loadStaffTickets();
            if (message.ticketId == _ticketId) {
              _upsertMessage(message);
              unawaited(_markRead());
            }
            await _applyRealtimeStaffTickets(tickets);
            _signalIncomingMessage(message);
          },
        )
        .subscribe();
  }

  Future<void> _applyRealtimeStaffTickets(
    List<Map<String, dynamic>> tickets,
  ) async {
    if (!mounted) return;
    if (_ticketId.isEmpty && tickets.isNotEmpty) {
      _ticketId = tickets.first['id']?.toString() ?? '';
      if (_ticketId.isNotEmpty) {
        await _loadTicket();
        await _loadMessages();
        await _subscribeToMessages();
        await _markRead();
      }
    } else if (_ticketId.isNotEmpty) {
      final current = tickets.where(
        (ticket) => ticket['id']?.toString() == _ticketId,
      );
      if (current.isNotEmpty) {
        _ticket = current.first;
      }
    }
    if (!mounted) return;
    setState(() => _staffTickets = tickets);
  }

  Future<void> _loadTicket() async {
    final ticket = await _supabase
        .from('support_tickets')
        .select()
        .eq('id', _ticketId)
        .maybeSingle();
    _ticket = ticket == null ? const {} : Map<String, dynamic>.from(ticket);
  }

  Future<void> _selectTicket(Map<String, dynamic> ticket) async {
    final id = ticket['id']?.toString() ?? '';
    if (id.isEmpty || id == _ticketId) return;
    setState(() {
      _loading = true;
      _ticketId = id;
      _ticket = ticket;
      _messages = const [];
    });
    try {
      await _loadTicket();
      await _loadMessages();
      await _subscribeToMessages();
      await _markRead();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMessages() async {
    final response = await _supabase
        .from('support_messages')
        .select()
        .eq('ticket_id', _ticketId)
        .order('created_at', ascending: true);
    _messages = (response as List)
        .cast<Map<String, dynamic>>()
        .map(_SupportChatMessage.fromMap)
        .toList();
  }

  Future<void> _subscribeToMessages() async {
    await _messagesChannel?.unsubscribe();
    _messagesChannel = _supabase.channel('support-messages-$_ticketId')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'support_messages',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'ticket_id',
          value: _ticketId,
        ),
        callback: (payload) {
          if (payload.newRecord.isEmpty) return;
          final next = _SupportChatMessage.fromMap(
            Map<String, dynamic>.from(payload.newRecord),
          );
          _upsertMessage(next);
          if (next.senderId != _supabase.auth.currentUser?.id) {
            _signalIncomingMessage(next);
            unawaited(_markRead());
          }
        },
      )
      ..subscribe();
  }

  Future<void> _markRead() async {
    if (_ticketId.isEmpty) return;
    try {
      await _supabase.rpc(
        'mark_support_messages_read',
        params: {'p_ticket_id': _ticketId},
      );
      await _supabase
          .from('push_notifications')
          .update({'read_at': DateTime.now().toIso8601String()})
          .eq('entity_id', _ticketId)
          .eq('type', 'SUPPORT_MESSAGE_RECEIVED')
          .isFilter('read_at', null);
    } catch (_) {}
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _ticketId.isEmpty || _sending) return;
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    setState(() => _sending = true);
    try {
      final row = await _supabase
          .from('support_messages')
          .insert({
            'ticket_id': _ticketId,
            'sender_id': user.id,
            'sender_name': _userName,
            'sender_role': _userRole,
            'text': text,
          })
          .select()
          .single();
      _messageController.clear();
      _upsertMessage(_SupportChatMessage.fromMap(row));

      await _supabase
          .from('support_tickets')
          .update({
            'status': _isStaff ? 'in_progress' : 'open',
            if (_isStaff) 'assigned_to': user.id,
            'updated_at': DateTime.now().toIso8601String(),
            'reason': text,
          })
          .eq('id', _ticketId);
      await _notifyNewSupportMessage(
        messageId: row['id']?.toString() ?? '',
        text: text,
        senderId: user.id,
      );
      _scrollToBottom();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _notifyNewSupportMessage({
    required String messageId,
    required String text,
    required String senderId,
  }) async {
    if (messageId.isEmpty) return;

    final targetId = _isStaff
        ? (_ticket['opened_by']?.toString() ?? '')
        : (_ticket['assigned_to']?.toString() ?? '');
    if (targetId.isEmpty || targetId == senderId) return;

    final preview = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    final shortPreview = preview.length > 120
        ? '${preview.substring(0, 117)}...'
        : preview;

    try {
      await NotificationDispatchService.instance.sendToUser(
        userId: targetId,
        type: 'SUPPORT_MESSAGE_RECEIVED',
        title: 'Suporte DeliGo',
        body: shortPreview,
        action: 'OPEN_SUPPORT_CHAT',
        entityId: _ticketId,
        channel: 'support',
        data: {'support_ticket_id': _ticketId, 'support_message_id': messageId},
        metadata: {
          'support_ticket_id': _ticketId,
          'support_message_id': messageId,
        },
        dispatchKey: 'support-message:$messageId:$targetId',
      );
    } catch (error) {
      // A push failure must never undo a message already persisted in the chat.
      debugPrint('Support message notification failed: $error');
    }
  }

  Future<void> _setTicketStatus(String status) async {
    if (!_isStaff || _ticketId.isEmpty) return;
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    final now = DateTime.now().toIso8601String();
    final isResolved =
        status == 'resolved' || status == 'closed' || status == 'completed';
    final update = <String, dynamic>{
      'status': status,
      'assigned_to': user.id,
      'updated_at': now,
      if (isResolved) 'resolved_by': user.id,
      if (isResolved) 'resolved_at': now,
      if (isResolved) 'resolution': 'Concluido pelo suporte',
    };
    await _supabase.from('support_tickets').update(update).eq('id', _ticketId);
    await _loadTicket();
    final tickets = await _loadStaffTickets();
    if (!mounted) return;
    setState(() => _staffTickets = tickets);
    await _notifyTicketStatus(status);

    if (isResolved) {
      final nextId = await _loadNextOpenTicket();
      if (!mounted) return;
      if (nextId.isEmpty) {
        setState(() {
          _ticketId = '';
          _ticket = const {};
          _messages = const [];
        });
      } else {
        final nextTicket = tickets.firstWhere(
          (ticket) => ticket['id']?.toString() == nextId,
          orElse: () => {'id': nextId},
        );
        await _selectTicket(nextTicket);
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ticket marcado em andamento.')),
        );
      }
    }
  }

  Future<void> _notifyTicketStatus(String status) async {
    final openedBy = _ticket['opened_by']?.toString() ?? '';
    final user = _supabase.auth.currentUser;
    if (openedBy.isEmpty || openedBy == user?.id) return;
    final isResolved = status == 'resolved';
    await NotificationDispatchService.instance.sendToUser(
      userId: openedBy,
      type: 'SUPPORT_UPDATED',
      title: isResolved ? 'Atendimento concluido' : 'Atendimento em andamento',
      body: isResolved
          ? 'O suporte concluiu o seu atendimento.'
          : 'O suporte esta a tratar do seu atendimento.',
      action: 'OPEN_SUPPORT_CHAT',
      entityId: _ticketId,
      channel: 'support',
      data: {'support_ticket_id': _ticketId, 'status': status},
      metadata: {'support_ticket_id': _ticketId, 'status': status},
    );
  }

  void _upsertMessage(_SupportChatMessage message) {
    final updated = [..._messages];
    final index = updated.indexWhere((item) => item.id == message.id);
    if (index >= 0) {
      updated[index] = message;
    } else {
      updated.add(message);
    }
    updated.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    if (!mounted) return;
    setState(() => _messages = updated);
    _scrollToBottom();
  }

  void _signalIncomingMessage(_SupportChatMessage message) {
    if (_signalledMessageIds.contains(message.id)) return;
    _signalledMessageIds.add(message.id);
    unawaited(
      PushNotificationService().showSupportMessageAlert(
        ticketId: message.ticketId,
        senderName: message.senderName,
        body: message.text,
        eventId: message.id,
      ),
    );
    if (!mounted) return;
    final ticketCode = message.ticketId.length >= 8
        ? message.ticketId.substring(0, 8)
        : message.ticketId;
    final title = _isStaff ? 'Nova mensagem' : 'Resposta do suporte';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$title de ${message.senderName} - Chat #$ticketCode'),
        action: SnackBarAction(
          label: 'Abrir',
          onPressed: () {
            final ticket = _staffTickets.firstWhere(
              (item) => item['id']?.toString() == message.ticketId,
              orElse: () => {'id': message.ticketId},
            );
            unawaited(_selectTicket(ticket));
          },
        ),
      ),
    );
  }

  void _scrollToBottom() {
    Future<void>.delayed(const Duration(milliseconds: 120), () {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 120,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: AppColors.primaryRed,
        foregroundColor: AppColors.cleanWhite,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _ticketId.isEmpty
          ? _emptySupportQueue()
          : Column(
              children: [
                if (_isStaff && widget.ticketId == null) _ticketSearchPanel(),
                _ticketHeader(),
                if (_isStaff) _ticketStatusBar(),
                Expanded(child: _messagesList()),
                _composer(),
              ],
            ),
    );
  }

  Widget _emptySupportQueue() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Nao ha tickets de suporte pendentes agora.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _ticketHeader() {
    final status = _ticket['status']?.toString() ?? 'open';
    final customer = _ticketCustomerName(_ticket);
    final phone = _ticketCustomerPhone(_ticket);
    final ticketCode = _ticketId.length >= 8
        ? _ticketId.substring(0, 8)
        : _ticketId;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      color: const Color(0xFFFFF7DF),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: AppColors.primaryRed.withValues(alpha: 0.12),
            child: const Icon(
              Icons.person_outline,
              color: AppColors.primaryRed,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  customer,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  phone,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.neutralGray),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '#$ticketCode',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              Text(
                _ticketStatusLabel(status),
                style: TextStyle(
                  color: _isPendingStatus(status)
                      ? AppColors.primaryRed
                      : AppColors.neutralGray,
                  fontWeight: _isPendingStatus(status)
                      ? FontWeight.w800
                      : FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _ticketStatusBar() {
    final status = _ticket['status']?.toString() ?? 'open';
    final isInProgress = status == 'in_progress';
    final isDone =
        status == 'resolved' || status == 'closed' || status == 'completed';
    return Material(
      color: Colors.white,
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: isInProgress || isDone
                    ? null
                    : () => _setTicketStatus('in_progress'),
                icon: const Icon(Icons.play_circle_outline),
                label: const Text('Em andamento'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: isDone ? null : () => _setTicketStatus('resolved'),
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Concluir'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ticketSearchPanel() {
    final query = _ticketQuery.trim().toLowerCase();
    final tickets = _staffTickets.where((ticket) {
      if (query.isEmpty) return true;
      final id = ticket['id']?.toString().toLowerCase() ?? '';
      final name = ticket['customer_name']?.toString().toLowerCase() ?? '';
      final phone = ticket['customer_phone']?.toString().toLowerCase() ?? '';
      final reason = ticket['reason']?.toString().toLowerCase() ?? '';
      return id.contains(query) ||
          name.contains(query) ||
          phone.contains(query) ||
          reason.contains(query);
    }).toList();
    tickets.sort((a, b) {
      final pendingCompare = (_isPendingTicket(a) ? 0 : 1).compareTo(
        _isPendingTicket(b) ? 0 : 1,
      );
      if (pendingCompare != 0) return pendingCompare;
      final aUpdated = DateTime.tryParse(a['updated_at']?.toString() ?? '');
      final bUpdated = DateTime.tryParse(b['updated_at']?.toString() ?? '');
      return (bUpdated ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
        aUpdated ?? DateTime.fromMillisecondsSinceEpoch(0),
      );
    });
    final pendingCount = tickets.where(_isPendingTicket).length;

    return Material(
      color: Colors.white,
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(
                  Icons.mark_chat_unread_outlined,
                  color: AppColors.primaryRed,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Mensagens pendentes',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: pendingCount > 0
                        ? AppColors.primaryRed
                        : AppColors.neutralGray.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$pendingCount',
                    style: TextStyle(
                      color: pendingCount > 0
                          ? Colors.white
                          : AppColors.neutralGray,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _ticketSearchController,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Pesquisar usuario, telefone ou ID do chat',
                suffixIcon: _ticketQuery.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Limpar',
                        onPressed: () {
                          _ticketSearchController.clear();
                          setState(() => _ticketQuery = '');
                        },
                        icon: const Icon(Icons.close),
                      ),
                border: const OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() => _ticketQuery = value),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 148,
              child: Scrollbar(
                controller: _ticketListController,
                thumbVisibility: true,
                child: ListView.separated(
                  controller: _ticketListController,
                  itemCount: tickets.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final ticket = tickets[index];
                    final id = ticket['id']?.toString() ?? '';
                    final code = id.length >= 8 ? id.substring(0, 8) : id;
                    final name = _ticketCustomerName(ticket);
                    final phone = _ticketCustomerPhone(ticket);
                    final status = ticket['status']?.toString() ?? 'open';
                    final pending = _isPendingStatus(status);
                    final selected = id == _ticketId;
                    return Material(
                      color: selected
                          ? AppColors.primaryRed.withValues(alpha: 0.08)
                          : pending
                          ? const Color(0xFFFFECEC)
                          : AppColors.softBackground,
                      borderRadius: BorderRadius.circular(8),
                      child: ListTile(
                        dense: true,
                        shape: RoundedRectangleBorder(
                          side: BorderSide(
                            color: pending
                                ? AppColors.primaryRed.withValues(alpha: 0.35)
                                : Colors.transparent,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        leading: CircleAvatar(
                          radius: 18,
                          backgroundColor: pending
                              ? AppColors.primaryRed
                              : Colors.white,
                          child: pending
                              ? const Icon(
                                  Icons.notifications_active_outlined,
                                  color: Colors.white,
                                  size: 19,
                                )
                              : Text(
                                  name.isEmpty ? 'U' : name[0].toUpperCase(),
                                ),
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _statusBadge(status),
                          ],
                        ),
                        subtitle: Text(
                          '$phone\nChat #$code',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _selectTicket(ticket),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusBadge(String status) {
    final pending = _isPendingStatus(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: pending ? AppColors.primaryRed : const Color(0xFFE8F5EE),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _ticketStatusLabel(status),
        style: TextStyle(
          color: pending ? Colors.white : const Color(0xFF0B6B4F),
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  bool _isPendingTicket(Map<String, dynamic> ticket) {
    return _isPendingStatus(ticket['status']?.toString() ?? 'open');
  }

  bool _isPendingStatus(String status) {
    return status == 'open' || status == 'pending';
  }

  String _ticketStatusLabel(String status) {
    switch (status) {
      case 'in_progress':
        return 'Em andamento';
      case 'resolved':
      case 'closed':
      case 'completed':
        return 'Concluido';
      case 'open':
      case 'pending':
      default:
        return 'Pendente';
    }
  }

  String _ticketCustomerName(Map<String, dynamic> ticket) {
    final name = ticket['customer_name']?.toString().trim() ?? '';
    return name.isEmpty ? 'Usuario DeliGo' : name;
  }

  String _ticketCustomerPhone(Map<String, dynamic> ticket) {
    final phone = ticket['customer_phone']?.toString().trim() ?? '';
    return phone.isEmpty ? 'Telefone nao registado' : phone;
  }

  Widget _messagesList() {
    if (_messages.isEmpty) {
      return const Center(child: Text('Envie uma mensagem para iniciar.'));
    }
    return Scrollbar(
      controller: _scrollController,
      thumbVisibility: true,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(12),
        itemCount: _messages.length,
        itemBuilder: (context, index) {
          final message = _messages[index];
          final isMe = message.senderId == _supabase.auth.currentUser?.id;
          return Align(
            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.78,
              ),
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isMe ? const Color(0xFF0B8F6A) : Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isMe)
                    Text(
                      message.senderName,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.neutralGray,
                      ),
                    ),
                  Text(
                    message.text,
                    style: TextStyle(
                      color: isMe ? Colors.white : Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _composer() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _messageController,
                minLines: 1,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Mensagem',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            const SizedBox(width: 8),
            CircleAvatar(
              backgroundColor: AppColors.primaryRed,
              child: IconButton(
                icon: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send, color: Colors.white),
                onPressed: _sending ? null : _sendMessage,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
