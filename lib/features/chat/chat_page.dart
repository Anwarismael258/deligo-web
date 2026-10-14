import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';

import '../../config/theme/app_colors.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/order_service.dart';
import '../../shared/models/message.dart';
import '../../shared/models/order.dart';
import '../../services/image_service.dart';
import '../../shared/widgets/profile_image_viewer.dart';
import '../../shared/utils/deligo_viewport.dart';
import 'chat_provider.dart';

class _ChatContact {
  final String label;
  final String name;
  final IconData icon;
  final String? avatarUrl;

  const _ChatContact({
    required this.label,
    required this.name,
    required this.icon,
    this.avatarUrl,
  });
}

class ChatPage extends StatefulWidget {
  final String orderId;
  final String? viewerRole;

  const ChatPage({super.key, required this.orderId, this.viewerRole});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final SupabaseClient _supabase = Supabase.instance.client;
  final ImageService _imageService = ImageService();
  final OrderService _orderService = OrderService();

  String _userRole = 'client';
  String _userName = '';
  Map<String, String> _orderContext = const {};
  bool _isLoadingOrderContext = true;
  bool _isUploadingAttachment = false;
  bool _showOrderDetails = false;
  String _activeAudience = 'client';
  List<OrderItem> _orderItems = const [];

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  Future<void> _loadUserInfo() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    Map<String, dynamic> profile = const {};
    try {
      final response = await _supabase
          .from('profiles')
          .select('full_name, role')
          .eq('id', user.id)
          .maybeSingle();
      profile = response ?? const {};
    } catch (error) {
      debugPrint('ChatPage: perfil indisponivel, a carregar mensagens: $error');
    }

    if (!mounted) return;

    final rawRole = (profile['role'] ?? 'client').toString().toLowerCase();
    final requestedRole = widget.viewerRole?.trim().toLowerCase() ?? '';
    final normalizedRole =
        requestedRole == 'restaurant' ||
            requestedRole == 'courier' ||
            requestedRole == 'client'
        ? requestedRole
        : rawRole.contains('restaurant')
        ? 'restaurant'
        : rawRole.contains('courier') || rawRole.contains('estafeta')
        ? 'courier'
        : rawRole;
    setState(() {
      _userName = profile['full_name'] ?? 'Usuario';
      _userRole = normalizedRole;
    });

    await _loadOrderContext();
    if (!mounted) return;
    context.read<ChatProvider>().loadMessages(widget.orderId);
  }

  Future<void> _loadOrderContext() async {
    try {
      final order = await _supabase
          .from('orders')
          .select(
            'id, client_id, customer_id, restaurant_id, courier_id, delivery_address, created_at',
          )
          .eq('id', widget.orderId)
          .maybeSingle();

      if (order == null) {
        if (!mounted) return;
        setState(() {
          _orderContext = const {};
          _isLoadingOrderContext = false;
          _orderItems = const [];
        });
        return;
      }

      final clientId = (order['client_id'] ?? order['customer_id'] ?? '')
          .toString();
      final courierId = (order['courier_id'] ?? '').toString();
      final restaurantId = (order['restaurant_id'] ?? '').toString();
      final results = await Future.wait<dynamic>([
        _fetchClientContact(widget.orderId, fallbackClientId: clientId),
        _fetchCourierContact(courierId),
        _fetchRestaurantContact(restaurantId),
        _orderService.getOrderItems(widget.orderId),
      ]);
      final clientProfile = results[0] as Map<String, String?>;
      final courierProfile = results[1] as Map<String, String?>;
      final restaurant = results[2] as Map<String, String?>;
      final items = results[3] as List<OrderItem>;

      if (!mounted) return;
      setState(() {
        _orderContext = {
          'order_id': widget.orderId,
          'delivery_address':
              (order['delivery_address'] ?? 'Endereco nao disponivel')
                  .toString(),
          'created_at': (order['created_at'] ?? '').toString(),
          'client_name':
              _normalizeContactValue(clientProfile['full_name']).isNotEmpty
              ? _normalizeContactValue(clientProfile['full_name'])
              : 'Cliente',
          'client_avatar_url': clientProfile['avatar_url'] ?? '',
          'restaurant_name':
              _normalizeContactValue(restaurant['name']).isNotEmpty
              ? _normalizeContactValue(restaurant['name'])
              : 'Restaurante',
          'restaurant_avatar_url': restaurant['avatar_url'] ?? '',
          'courier_name': courierId.isNotEmpty
              ? (_normalizeContactValue(courierProfile['full_name']).isNotEmpty
                    ? _normalizeContactValue(courierProfile['full_name'])
                    : 'Estafeta')
              : 'Aguardando estafeta',
          'courier_avatar_url': courierProfile['avatar_url'] ?? '',
        };
        _isLoadingOrderContext = false;
        _orderItems = items;
      });
    } catch (e) {
      debugPrint(
        'ChatPage: erro ao carregar contexto do pedido ${widget.orderId}: $e',
      );
      if (!mounted) return;
      setState(() {
        _orderContext = const {};
        _isLoadingOrderContext = false;
        _orderItems = const [];
      });
    }
  }

  Future<Map<String, String?>> _fetchClientContact(
    String orderId, {
    String? fallbackClientId,
  }) async {
    try {
      final payload = await _supabase.rpc(
        'get_order_client_contact',
        params: {'p_order_id': orderId},
      );
      if (payload is Map) {
        final result = {
          'full_name': payload['full_name']?.toString(),
          'avatar_url': payload['avatar_url']?.toString(),
        };
        if ((result['avatar_url'] ?? '').trim().isNotEmpty) return result;
      }
    } catch (error) {
      debugPrint('ChatPage: erro ao carregar contacto do cliente: $error');
    }

    final clientId = (fallbackClientId ?? '').trim();
    if (clientId.isEmpty) {
      return const {'full_name': null};
    }

    try {
      final profile = await _supabase
          .from('profiles')
          .select('full_name, avatar_url')
          .eq('id', clientId)
          .maybeSingle();
      return {
        'full_name': profile?['full_name']?.toString(),
        'avatar_url': profile?['avatar_url']?.toString(),
      };
    } catch (_) {
      return const {'full_name': null};
    }
  }

  Future<Map<String, String?>> _fetchCourierContact(String courierId) async {
    if (courierId.trim().isEmpty) {
      return const {'full_name': null};
    }

    try {
      final courier = await _supabase
          .from('couriers')
          .select('full_name, avatar_url')
          .eq('id', courierId)
          .maybeSingle();
      return {
        'full_name': courier?['full_name']?.toString(),
        'avatar_url': courier?['avatar_url']?.toString(),
      };
    } catch (_) {
      try {
        final profile = await _supabase
            .from('profiles')
            .select('full_name')
            .eq('id', courierId)
            .maybeSingle();
        return {
          'full_name': profile?['full_name']?.toString(),
          'avatar_url': profile?['avatar_url']?.toString(),
        };
      } catch (_) {
        return const {'full_name': null};
      }
    }
  }

  Future<Map<String, String?>> _fetchRestaurantContact(
    String restaurantId,
  ) async {
    if (restaurantId.trim().isEmpty) {
      return const {'name': null};
    }

    try {
      final restaurant = await _supabase
          .from('restaurants')
          .select('name, image_url')
          .eq('id', restaurantId)
          .maybeSingle();
      final result = {
        'name': restaurant?['name']?.toString(),
        'avatar_url': restaurant?['image_url']?.toString(),
      };
      if ((result['avatar_url'] ?? '').trim().isNotEmpty) return result;
      final ownerProfile = await _supabase
          .from('profiles')
          .select('avatar_url')
          .eq('id', restaurantId)
          .maybeSingle();
      return {...result, 'avatar_url': ownerProfile?['avatar_url']?.toString()};
    } catch (_) {
      return const {'name': null};
    }
  }

  String _normalizeContactValue(String? value) {
    final trimmed = (value ?? '').trim();
    if (trimmed.isEmpty || trimmed == '-' || trimmed.toLowerCase() == 'null') {
      return '';
    }
    return trimmed;
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    context.read<ChatProvider>().sendMessage(
      text,
      _userName,
      _userRole,
      null,
      null,
    );
    _messageController.clear();

    Future.delayed(const Duration(milliseconds: 120), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 120,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendAttachment(ImageSource source) async {
    if (_isUploadingAttachment) return;
    setState(() => _isUploadingAttachment = true);
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    final folder = '${user.id}/${widget.orderId}';
    final url = await _imageService.uploadImageFromSource(
      'chat-attachments',
      folder,
      source,
    );

    if (!mounted) return;
    setState(() => _isUploadingAttachment = false);

    if (url == null || url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nao foi possivel enviar a imagem agora.'),
        ),
      );
      return;
    }

    context.read<ChatProvider>().sendMessage(
      '',
      _userName,
      _userRole,
      url,
      'image',
    );
  }

  void _openEmojiPicker() {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        final emojis = [
          '\u{1F600}',
          '\u{1F601}',
          '\u{1F602}',
          '\u{1F923}',
          '\u{1F60A}',
          '\u{1F60D}',
          '\u{1F618}',
          '\u{1F60B}',
          '\u{1F60E}',
          '\u{1F973}',
          '\u{1F605}',
          '\u{1F607}',
          '\u{1F642}',
          '\u{1F609}',
          '\u{1F60C}',
          '\u{1F622}',
          '\u{1F621}',
          '\u{1F44D}',
          '\u{1F44E}',
          '\u{1F64F}',
          '\u{1F44F}',
          '\u{1F4AA}',
          '\u{1F525}',
          '\u{1F389}',
          '\u{1F4AF}',
          '\u{2705}',
          '\u{274C}',
          '\u{1F4E6}',
          '\u{1F6F5}',
        ];
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: emojis.map((emoji) {
                return GestureDetector(
                  onTap: () {
                    Navigator.of(context).pop();
                    _messageController.text =
                        '${_messageController.text}$emoji';
                    _messageController.selection = TextSelection.collapsed(
                      offset: _messageController.text.length,
                    );
                    setState(() {});
                  },
                  child: Text(emoji, style: const TextStyle(fontSize: 26)),
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  void _openAttachmentPicker() {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Foto da galeria'),
                onTap: () {
                  Navigator.of(context).pop();
                  _sendAttachment(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Tirar foto'),
                onTap: () {
                  Navigator.of(context).pop();
                  _sendAttachment(ImageSource.camera);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _openImagePreview(String url) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 4,
            child: Image.network(url, fit: BoxFit.contain),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final restaurantMode = _userRole == 'restaurant';
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: restaurantMode
          ? const Color(0xFF061426)
          : const Color(0xFFE8DED4),
      appBar: AppBar(
        backgroundColor: restaurantMode
            ? const Color(0xFF07182E)
            : const Color(0xFFFFFFFF),
        foregroundColor: restaurantMode
            ? Colors.white
            : const Color(0xFF0F172A),
        elevation: 0,
        titleSpacing: 0,
        leading: IconButton(
          tooltip: 'Voltar',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
        title: Row(
          children: [
            _buildAvatar(
              url: _activeChatAvatarUrl,
              icon: _chatRoleIcon(),
              radius: 18,
              backgroundColor: restaurantMode
                  ? const Color(0xFFEF233C)
                  : const Color(0xFFFFE7E9),
              iconColor: restaurantMode
                  ? Colors.white
                  : const Color(0xFFFF2938),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _chatTitle(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: restaurantMode
                          ? Colors.white
                          : const Color(0xFF0F172A),
                    ),
                  ),
                  Text(
                    'Pedido #${widget.orderId.substring(0, 8)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: restaurantMode
                          ? const Color(0xFFB7C7DC)
                          : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final viewport = DeligoViewport.fromConstraints(constraints);
          final chromeMaxHeight = math.min(
            viewport.height * (viewport.isCompact ? 0.34 : 0.40),
            viewport.isCompact ? 168.0 : 250.0,
          );
          return Column(
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: chromeMaxHeight),
                child: DeligoViewportScrollArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildOrderHeader(),
                      if (restaurantMode)
                        _buildRestaurantConversationControls(),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(child: _buildChatBackdrop()),
                    Consumer<ChatProvider>(
                      builder: (context, chatProvider, child) {
                        if (chatProvider.isLoading) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }

                        if (chatProvider.messages.isEmpty) {
                          return Center(
                            child: Container(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 24,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.92),
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: const Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.chat_bubble_outline_rounded,
                                    size: 30,
                                    color: Color(0xFF0B8F6A),
                                  ),
                                  SizedBox(height: 6),
                                  Text(
                                    'Nenhuma mensagem ainda',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.darkGray,
                                    ),
                                  ),
                                  SizedBox(height: 3),
                                  Text(
                                    'Envie uma mensagem para iniciar a conversa.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: AppColors.neutralGray,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }

                        return ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
                          itemCount: chatProvider.messages.length,
                          itemBuilder: (context, index) {
                            final message = chatProvider.messages[index];
                            final previous = index > 0
                                ? chatProvider.messages[index - 1]
                                : null;
                            final isMe =
                                message.senderId ==
                                _supabase.auth.currentUser?.id;
                            final showHeader =
                                previous == null ||
                                previous.senderId != message.senderId ||
                                !_isSameMinute(
                                  previous.timestamp,
                                  message.timestamp,
                                );
                            return _buildMessageBubble(
                              message,
                              isMe,
                              showHeader: showHeader,
                            );
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),
              _buildComposer(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildChatBackdrop() {
    final restaurantMode = _userRole == 'restaurant';
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: restaurantMode
              ? [const Color(0xFF061426), const Color(0xFF09223E)]
              : [const Color(0xFFF6EFE7), const Color(0xFFE8DED4)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: CustomPaint(painter: _ChatPatternPainter()),
    );
  }

  Widget _buildRestaurantConversationControls() {
    final hasCourier =
        (_orderContext['courier_name'] ?? '').trim().isNotEmpty &&
        _orderContext['courier_name'] != 'Aguardando estafeta';
    return Container(
      color: const Color(0xFF07182E),
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 6),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Chat do pedido',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Icon(
                Icons.verified_user_outlined,
                color: Color(0xFF4ADE80),
                size: 18,
              ),
              const SizedBox(width: 5),
              const Text(
                'Monitorado pela DeliGo',
                style: TextStyle(color: Color(0xFFB7C7DC), fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              Expanded(
                child: _buildAudienceChip(
                  key: 'client',
                  icon: Icons.person_rounded,
                  label: 'Cliente',
                  detail: _orderContext['client_name'] ?? 'Cliente',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildAudienceChip(
                  key: 'courier',
                  icon: Icons.delivery_dining_rounded,
                  label: 'Estafeta',
                  detail: hasCourier
                      ? _orderContext['courier_name']!
                      : 'Aguardando recolha',
                  disabled: !hasCourier,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildAudienceChip(
                  key: 'support',
                  icon: Icons.headset_mic_outlined,
                  label: 'Suporte',
                  detail: 'DeliGo 24/7',
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildQuickMessage(
                'Pedido pronto',
                Icons.check_circle_outline,
                const Color(0xFF22C55E),
                'Pedido pronto! Já estamos a aguardar a recolha.',
              ),
              _buildQuickMessage(
                'Vai demorar',
                Icons.schedule_outlined,
                const Color(0xFF60A5FA),
                'O pedido precisa de mais alguns minutos. Pedimos desculpa.',
              ),
              _buildQuickMessage(
                'Há um problema',
                Icons.warning_amber_rounded,
                const Color(0xFFFBBF24),
                'Há um problema com este pedido. Precisamos de ajuda.',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAudienceChip({
    required String key,
    required IconData icon,
    required String label,
    required String detail,
    bool disabled = false,
  }) {
    final selected = _activeAudience == key;
    return InkWell(
      onTap: disabled ? null : () => setState(() => _activeAudience = key),
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF5C1924) : const Color(0xFF0D2038),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? const Color(0xFFEF233C) : const Color(0xFF2A4261),
          ),
        ),
        child: Row(
          children: [
            _buildAvatar(
              url: _avatarForAudience(key),
              icon: icon,
              radius: 13,
              backgroundColor: selected
                  ? const Color(0xFF7A2431)
                  : const Color(0xFF18304D),
              iconColor: disabled ? const Color(0xFF70849B) : Colors.white,
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                detail == label ? label : detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: disabled ? const Color(0xFF70849B) : Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickMessage(
    String label,
    IconData icon,
    Color color,
    String message,
  ) {
    return SizedBox(
      width: 150,
      child: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: OutlinedButton.icon(
          onPressed: () {
            _messageController.text = message;
            _messageController.selection = TextSelection.collapsed(
              offset: message.length,
            );
            setState(() {});
          },
          icon: Icon(icon, size: 17, color: color),
          label: Text(label, overflow: TextOverflow.ellipsis),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: BorderSide(color: color.withValues(alpha: 0.75)),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
      ),
    );
  }

  Widget _buildComposer() {
    final restaurantMode = _userRole == 'restaurant';
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      decoration: BoxDecoration(
        color: restaurantMode
            ? const Color(0xFF07182E)
            : const Color(0xFFF2F0EC),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    IconButton(
                      constraints: const BoxConstraints.tightFor(
                        width: 36,
                        height: 36,
                      ),
                      padding: EdgeInsets.zero,
                      icon: Icon(
                        Icons.emoji_emotions_outlined,
                        color: Colors.grey.shade500,
                      ),
                      onPressed: _openEmojiPicker,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        minLines: 1,
                        maxLines: 4,
                        decoration: InputDecoration(
                          hintText: 'Escrever uma mensagem...',
                          hintMaxLines: 1,
                          hintStyle: TextStyle(color: Colors.grey.shade600),
                          isDense: true,
                          filled: true,
                          fillColor: Colors.white,
                          border: InputBorder.none,
                        ),
                        style: TextStyle(
                          color: const Color(0xFF111827),
                          fontSize: 14,
                          height: 1.25,
                        ),
                        cursorColor: const Color(0xFF111827),
                        keyboardAppearance: restaurantMode
                            ? Brightness.dark
                            : Brightness.light,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                    IconButton(
                      constraints: const BoxConstraints.tightFor(
                        width: 36,
                        height: 36,
                      ),
                      padding: EdgeInsets.zero,
                      icon: Icon(
                        Icons.attach_file_rounded,
                        color: Colors.grey.shade500,
                      ),
                      onPressed: _isUploadingAttachment
                          ? null
                          : _openAttachmentPicker,
                    ),
                    IconButton(
                      constraints: const BoxConstraints.tightFor(
                        width: 36,
                        height: 36,
                      ),
                      padding: EdgeInsets.zero,
                      icon: Icon(
                        Icons.photo_camera_outlined,
                        color: Colors.grey.shade500,
                      ),
                      onPressed: _isUploadingAttachment
                          ? null
                          : () => _sendAttachment(ImageSource.camera),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 20,
              backgroundColor: restaurantMode
                  ? const Color(0xFFEF233C)
                  : const Color(0xFF0B8F6A),
              child: IconButton(
                icon: const Icon(Icons.send_rounded, color: Colors.white),
                onPressed: _sendMessage,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderHeader() {
    if (_isLoadingOrderContext) {
      return const LinearProgressIndicator(minHeight: 2);
    }

    if (_orderContext.isEmpty) {
      return const SizedBox.shrink();
    }

    final createdAt =
        DateTime.tryParse(_orderContext['created_at'] ?? '') ?? DateTime.now();
    final screen = MediaQuery.of(context).size;
    final compact = screen.width < 390 || screen.height < 760;
    final restaurantMode = _userRole == 'restaurant';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(10, 5, 10, 4),
      padding: EdgeInsets.all(compact ? 8 : 9),
      decoration: BoxDecoration(
        color: restaurantMode
            ? const Color(0xFF0D2038)
            : const Color(0xFFFFF3C8),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: restaurantMode
              ? const Color(0xFF284363)
              : const Color(0xFFFFE28E),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Conversa do pedido',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: restaurantMode
                        ? Colors.white
                        : Colors.brown.shade800,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  setState(() => _showOrderDetails = !_showOrderDetails);
                },
                style: TextButton.styleFrom(
                  foregroundColor: restaurantMode
                      ? const Color(0xFF93C5FD)
                      : const Color(0xFF0B8F6A),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 8 : 10,
                    vertical: 6,
                  ),
                ),
                icon: Icon(
                  _showOrderDetails
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 18,
                ),
                label: Text(
                  _showOrderDetails ? 'Esconder detalhes' : 'Mostrar detalhes',
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (_showOrderDetails)
            Text(
              '${_formatDateTime(createdAt)} • ${_orderContext['delivery_address']}',
              style: TextStyle(
                height: 1.35,
                color: restaurantMode
                    ? const Color(0xFFB7C7DC)
                    : Colors.brown.shade700,
              ),
            ),
          if (!_showOrderDetails)
            Text(
              'Pedido #${widget.orderId.substring(0, 8)}',
              style: TextStyle(
                height: 1.35,
                color: restaurantMode
                    ? const Color(0xFFB7C7DC)
                    : Colors.brown.shade700,
              ),
            ),
          if (_showOrderDetails) ..._buildContactCards(),
          if (_showOrderDetails && _orderItems.isNotEmpty) ...[
            const SizedBox(height: 10),
            ..._orderItems.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    const Icon(
                      Icons.receipt_long_outlined,
                      size: 16,
                      color: Color(0xFF0B8F6A),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${item.quantity}x ${item.menuItem?.name ?? 'Item'}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      '${item.subtotal.toStringAsFixed(0)} MZN',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildContactCards() {
    final contacts = <_ChatContact>[];
    switch (_userRole) {
      case 'restaurant':
        contacts.add(
          _ChatContact(
            label: 'Cliente',
            name: _orderContext['client_name'] ?? 'Cliente',
            icon: Icons.person_outline,
            avatarUrl: _orderContext['client_avatar_url'],
          ),
        );
        contacts.add(
          _ChatContact(
            label: 'Estafeta',
            name: _orderContext['courier_name'] ?? 'Estafeta',
            icon: Icons.delivery_dining_outlined,
            avatarUrl: _orderContext['courier_avatar_url'],
          ),
        );
        break;
      case 'courier':
        contacts.add(
          _ChatContact(
            label: 'Restaurante',
            name: _orderContext['restaurant_name'] ?? 'Restaurante',
            icon: Icons.storefront_outlined,
            avatarUrl: _orderContext['restaurant_avatar_url'],
          ),
        );
        contacts.add(
          _ChatContact(
            label: 'Cliente',
            name: _orderContext['client_name'] ?? 'Cliente',
            icon: Icons.person_outline,
            avatarUrl: _orderContext['client_avatar_url'],
          ),
        );
        break;
      default:
        contacts.add(
          _ChatContact(
            label: 'Restaurante',
            name: _orderContext['restaurant_name'] ?? 'Restaurante',
            icon: Icons.storefront_outlined,
            avatarUrl: _orderContext['restaurant_avatar_url'],
          ),
        );
        contacts.add(
          _ChatContact(
            label: 'Estafeta',
            name: _orderContext['courier_name'] ?? 'Estafeta',
            icon: Icons.delivery_dining_outlined,
            avatarUrl: _orderContext['courier_avatar_url'],
          ),
        );
        break;
    }

    final width = MediaQuery.sizeOf(context).width;
    final cardWidth = (width - 42) / contacts.length;
    return [
      const SizedBox(height: 6),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: contacts
            .map(
              (contact) =>
                  SizedBox(width: cardWidth, child: _contactCard(contact)),
            )
            .toList(),
      ),
    ];
  }

  Widget _contactCard(_ChatContact contact) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProfileImageViewer(
                imageUrl: contact.avatarUrl,
                size: 28,
                radius: 10,
                fallbackIcon: contact.icon,
                backgroundColor: const Color(
                  0xFF0B8F6A,
                ).withValues(alpha: 0.12),
                iconColor: const Color(0xFF0B8F6A),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      contact.label,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                        color: Colors.brown.shade600,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      contact.name,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(
    Message message,
    bool isMe, {
    required bool showHeader,
  }) {
    final restaurantMode = _userRole == 'restaurant';
    final bubbleColor = restaurantMode
        ? (isMe ? const Color(0xFF641C2A) : const Color(0xFF142A45))
        : (isMe ? const Color(0xFFDCF8C6) : Colors.white);
    final timeColor = restaurantMode
        ? const Color(0xFFB7C7DC)
        : (isMe ? const Color(0xFF5D7C65) : Colors.grey.shade600);
    final isRead = message.readAt != null;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: Radius.circular(isMe ? 18 : 4),
      bottomRight: Radius.circular(isMe ? 4 : 18),
    );

    return Padding(
      padding: EdgeInsets.only(
        top: showHeader ? 10 : 3,
        bottom: 3,
        left: isMe ? 58 : 0,
        right: isMe ? 0 : 58,
      ),
      child: Column(
        crossAxisAlignment: isMe
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          if (showHeader && !isMe)
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 4),
              child: Text(
                _getRoleLabel(message.senderRole, message.senderName),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: restaurantMode
                      ? const Color(0xFFD6E4F5)
                      : _getRoleColor(message.senderRole),
                ),
              ),
            ),
          Material(
            color: Colors.transparent,
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.78,
              ),
              padding: const EdgeInsets.fromLTRB(12, 9, 12, 8),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: radius,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (message.text.trim().isNotEmpty)
                    Text(
                      message.text,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.35,
                        color: restaurantMode
                            ? Colors.white
                            : const Color(0xFF111B21),
                      ),
                    ),
                  if (message.attachmentUrl != null &&
                      message.attachmentUrl!.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () =>
                          _openImagePreview(message.attachmentUrl!.trim()),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          message.attachmentUrl!.trim(),
                          width: 240,
                          height: 180,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 5),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        _formatTime(message.timestamp),
                        style: TextStyle(fontSize: 11, color: timeColor),
                      ),
                      if (isMe) ...[
                        const SizedBox(width: 4),
                        Icon(
                          isRead ? Icons.done_all_rounded : Icons.check_rounded,
                          size: 16,
                          color: isRead
                              ? const Color(0xFF53BDEB)
                              : const Color(0xFF7FA08D),
                        ),
                      ],
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

  String? get _activeChatAvatarUrl {
    switch (_userRole) {
      case 'restaurant':
        return _orderContext['client_avatar_url'];
      case 'courier':
        return _orderContext['restaurant_avatar_url'];
      default:
        return _orderContext['restaurant_avatar_url'];
    }
  }

  String? _avatarForAudience(String key) {
    switch (key) {
      case 'client':
        return _orderContext['client_avatar_url'];
      case 'courier':
        return _orderContext['courier_avatar_url'];
      default:
        return null;
    }
  }

  Widget _buildAvatar({
    required String? url,
    required IconData icon,
    required double radius,
    required Color backgroundColor,
    required Color iconColor,
  }) {
    final imageUrl = (url ?? '').trim();
    return ProfileImageViewer(
      imageUrl: imageUrl,
      size: radius * 2,
      radius: radius,
      fallbackIcon: icon,
      backgroundColor: backgroundColor,
      iconColor: iconColor,
    );
  }

  String _chatTitle() {
    final clientName =
        (_orderContext['client_name']?.toString().trim().isNotEmpty ?? false)
        ? _orderContext['client_name'].toString().trim()
        : 'Cliente';
    final restaurantName =
        (_orderContext['restaurant_name']?.toString().trim().isNotEmpty ??
            false)
        ? _orderContext['restaurant_name'].toString().trim()
        : 'Restaurante';
    switch (_userRole) {
      case 'restaurant':
        return clientName;
      case 'courier':
        return '$clientName | $restaurantName';
      default:
        return restaurantName;
    }
  }

  IconData _chatRoleIcon() {
    switch (_userRole) {
      case 'restaurant':
        return Icons.storefront_outlined;
      case 'courier':
        return Icons.delivery_dining_outlined;
      default:
        return Icons.person_outline;
    }
  }

  bool _isSameMinute(DateTime a, DateTime b) {
    return a.year == b.year &&
        a.month == b.month &&
        a.day == b.day &&
        a.hour == b.hour &&
        a.minute == b.minute;
  }

  Color _getRoleColor(String role) {
    switch (role) {
      case 'restaurant':
        return Colors.deepOrange;
      case 'courier':
        return Colors.blue.shade700;
      default:
        return AppColors.primaryRed;
    }
  }

  String _getRoleLabel(String role, String name) {
    switch (role) {
      case 'restaurant':
        return 'Restaurante';
      case 'courier':
        return 'Estafeta';
      default:
        return name.isNotEmpty ? name : 'Cliente';
    }
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  String _formatDateTime(DateTime time) {
    final day = time.day.toString().padLeft(2, '0');
    final month = time.month.toString().padLeft(2, '0');
    final year = time.year.toString();
    return '$day/$month/$year ${_formatTime(time)}';
  }
}

class _ChatPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;

    for (double y = 24; y < size.height; y += 56) {
      for (double x = (y ~/ 56).isEven ? 18 : 42; x < size.width; x += 56) {
        canvas.drawCircle(Offset(x, y), 10, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
