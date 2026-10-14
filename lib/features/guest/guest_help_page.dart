import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

class GuestHelpPage extends StatelessWidget {
  const GuestHelpPage({super.key});

  static const _items = [
    ('Posso explorar sem conta?', 'Sim. Pode descobrir restaurantes, consultar menus e preparar o carrinho como visitante.'),
    ('Quando preciso de criar uma conta?', 'A autenticação é necessária antes de finalizar uma encomenda ou efectuar um pagamento.'),
    ('O que acontece ao meu carrinho?', 'O carrinho de visitante fica guardado localmente e pode ser recuperado depois do login ou registo.'),
    ('Como falo com o suporte?', 'Pode ligar para 841130015 ou enviar uma mensagem pelo Facebook oficial da DeliGo.'),
    ('Quero ser parceiro.', 'Use o botão “Ser parceiro” para iniciar o registo real de restaurante.'),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF020817),
    appBar: AppBar(backgroundColor: const Color(0xFF020817), foregroundColor: Colors.white, title: const Text('Ajuda DeliGo')),
    body: ListView(padding: const EdgeInsets.all(24), children: [
      const Text('Perguntas e respostas', style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900)),
      const SizedBox(height: 8),
      const Text('Informação clara para começar a explorar a DeliGo.', style: TextStyle(color: Color(0xFFB9D7FF))),
      const SizedBox(height: 24),
      ..._items.map((item) => Card(color: const Color(0xFF07152D), child: ExpansionTile(iconColor: const Color(0xFFFF4D0A), collapsedIconColor: const Color(0xFFFF7A45), title: Text(item.$1, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)), children: [Padding(padding: const EdgeInsets.fromLTRB(18, 0, 18, 18), child: Text(item.$2, style: const TextStyle(color: Color(0xFFB9D7FF))))]))),
      const SizedBox(height: 22),
      FilledButton.icon(onPressed: () => launchUrl(Uri.parse('https://www.facebook.com/profile.php?id=61588898956501'), mode: LaunchMode.externalApplication), icon: const Icon(Icons.facebook), label: const Text('Enviar mensagem no Facebook')),
      const SizedBox(height: 10),
      OutlinedButton.icon(onPressed: () => launchUrl(Uri(scheme: 'tel', path: '841130015')), icon: const Icon(Icons.call_outlined), label: const Text('Ligar para o suporte 24/7')),
      const SizedBox(height: 16),
      TextButton(onPressed: () => context.go('/home'), child: const Text('Voltar ao início')),
    ]),
  );
}
