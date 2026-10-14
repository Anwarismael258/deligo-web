import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../config/theme/app_colors.dart';
import '../../services/deligo_ai_service.dart';

class DeligoAiChatPage extends StatefulWidget {
  const DeligoAiChatPage({super.key});

  @override
  State<DeligoAiChatPage> createState() => _DeligoAiChatPageState();
}

class _DeligoAiChatPageState extends State<DeligoAiChatPage> {
  final _controller = TextEditingController();
  final _messages = <({bool mine, String text})>[];
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _needsLogin(String text) => RegExp(
    r'\b(meu|minha|meus|minhas|pedido|encomenda|saldo|carteira|pagamento|levantamento|depósito|kyc|documento|conta|reembolso)\b',
    caseSensitive: false,
  ).hasMatch(text);

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    _controller.clear();
    setState(() {
      _messages.add((mine: true, text: text));
      _sending = true;
    });
    if (_needsLogin(text)) {
      setState(() {
        _messages.add((
          mine: false,
          text:
              'Para consultar dados pessoais, um pedido, saldo ou pagamento, entra primeiro na tua conta.',
        ));
        _sending = false;
      });
      return;
    }
    try {
      final answer = await DeligoAiService.instance.ask(message: text);
      if (!mounted) return;
      setState(() => _messages.add((mine: false, text: answer)));
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _messages.add((
          mine: false,
          text:
              'Não consegui responder agora. Podes entrar na conta e falar com o apoio DeliGo.',
        )),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DeliGo IA'),
        actions: [
          TextButton(
            onPressed: () => context.go('/login'),
            child: const Text('Entrar'),
          ),
        ],
      ),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 16, 18, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Pergunta sobre a DeliGo, entregas, restaurantes ou como ser estafeta. Para dados pessoais, entra na conta.',
                style: TextStyle(color: AppColors.neutralGray),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                return Align(
                  alignment: message.mine
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    constraints: const BoxConstraints(maxWidth: 330),
                    decoration: BoxDecoration(
                      color: message.mine
                          ? AppColors.primaryRed
                          : const Color(0xfff1f3f6),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      message.text,
                      style: TextStyle(
                        color: message.mine ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: 'Pergunta à DeliGo IA',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
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
