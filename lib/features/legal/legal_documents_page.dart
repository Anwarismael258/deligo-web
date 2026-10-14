import 'package:flutter/material.dart';

import '../../config/theme/app_colors.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _LegalScaffold(
      title: 'Politica de Privacidade',
      children: [
        _LegalAside(
          lastUpdated: '19 de Setembro de 2026 · Versão 1.0',
          country: 'República de Moçambique',
        ),
        SizedBox(height: 18),
        _SectionTitle('1. OBJETIVO'),
        _Paragraph(
          'Esta Politica de Privacidade explica como a DeliGo recolhe, utiliza, partilha e protege dados pessoais de clientes, estafetas, restaurantes e administradores no ambito da utilizacao da aplicacao e servicos associados.',
        ),
        _SectionTitle('2. RESPONSAVEL PELOS DADOS'),
        _Paragraph(
          'A Deligo Triunfal, LDA atua como responsavel pelo tratamento dos dados pessoais recolhidos atraves da plataforma DeliGo.',
        ),
        _SectionTitle('3. DADOS QUE PODEMOS RECOLHER'),
        _SubSectionTitle('3.1 Dados de conta'),
        _BulletList(
          items: [
            'Nome e dados de perfil',
            'Numero de telefone',
            'Email, quando fornecido',
            'Foto de perfil, quando enviada',
          ],
        ),
        _SubSectionTitle('3.2 Dados de verificacao e compliance'),
        _BulletList(
          items: [
            'Documentos de identificacao e respetiva informacao',
            'Selfie ou foto para verificacao',
            'Dados necessarios para prevencao de fraude e cumprimento legal',
          ],
        ),
        _SubSectionTitle('3.3 Dados de pedidos e pagamentos'),
        _BulletList(
          items: [
            'Historico de pedidos',
            'Endereco de entrega e coordenadas relacionadas',
            'Valores, taxas e estado das transacoes',
            'Registos de wallet, depositos e levantamentos',
          ],
        ),
        _SubSectionTitle('3.4 Dados de localizacao'),
        _BulletList(
          items: [
            'Localizacao aproximada e precisa para mapas e cobertura',
            'Rastreamento do pedido e do estafeta',
            'Calculo de rotas e tempos estimados',
          ],
        ),
        _SubSectionTitle('3.5 Comunicacoes e dados tecnicos'),
        _BulletList(
          items: [
            'Mensagens de chat e suporte',
            'Notificacoes push e preferencias',
            'Identificadores da aplicacao, analytics, crash logs e diagnosticos',
          ],
        ),
        _SectionTitle('4. COMO UTILIZAMOS OS DADOS'),
        _BulletList(
          items: [
            'Criar e gerir contas',
            'Processar pedidos, entregas e levantamentos',
            'Processar pagamentos e reconciliacoes',
            'Ativar chat, notificacoes e suporte',
            'Prevenir fraude e reforcar a seguranca',
            'Cumprir obrigacoes legais, fiscais e regulatorias',
            'Melhorar o desempenho e a confiabilidade da plataforma',
          ],
        ),
        _SectionTitle('5. PARTILHA DE DADOS'),
        _Paragraph(
          'Clientes, restaurantes e estafetas podem ver os dados minimos necessarios para executar um pedido. Tambem podemos partilhar dados com prestadores de pagamentos, infraestrutura, analytics, suporte tecnico e autoridades competentes quando exigido por lei.',
        ),
        _SectionTitle('6. RETENCAO'),
        _Paragraph(
          'Mantemos os dados pelo tempo necessario para prestar o servico, cumprir requisitos legais, prevenir fraude, resolver disputas e manter a integridade operacional e financeira da plataforma.',
        ),
        _SectionTitle('7. SEGURANCA'),
        _Paragraph(
          'Adotamos medidas tecnicas e organizacionais para proteger os dados, incluindo controlos de acesso, autenticacao, validacoes do lado do servidor e monitorizacao. Nenhum sistema e 100% seguro, mas trabalhamos continuamente para reduzir riscos.',
        ),
        _SectionTitle('8. DIREITOS DO UTILIZADOR'),
        _BulletList(
          items: [
            'Solicitar acesso aos seus dados',
            'Solicitar correcao de dados',
            'Solicitar eliminacao ou encerramento de conta, quando possivel',
            'Retirar consentimentos, quando o tratamento depender de consentimento',
          ],
        ),
        _Paragraph(
          'Os pedidos de eliminacao de conta podem ser feitos diretamente na aplicacao DeliGo, na secao Configuracoes. Pedidos com saldo, pedidos ativos, disputas ou obrigacoes legais podem passar por revisao manual antes da eliminacao definitiva.',
        ),
        _SectionTitle('9. TECNOLOGIAS SEMELHANTES A COOKIES'),
        _Paragraph(
          'A aplicacao pode utilizar identificadores e tecnologias semelhantes para manter sessao, prevenir fraude, suportar analytics e melhorar o servico.',
        ),
        _SectionTitle('10. ALTERACOES'),
        _Paragraph(
          'Podemos atualizar esta politica periodicamente. A versao mais recente deve estar disponivel nos canais oficiais da DeliGo.',
        ),
        _SectionTitle('11. CONTACTO'),
        _ContactBlock(),
      ],
    );
  }
}

class RefundPolicyPage extends StatelessWidget {
  const RefundPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _LegalScaffold(
      title: 'Pagamentos e Reembolsos',
      children: [
        _LegalAside(
          lastUpdated: '19 de Setembro de 2026 · Versão 1.0',
          country: 'República de Moçambique',
        ),
        SizedBox(height: 18),
        _SectionTitle('1. PAGAMENTOS SUPORTADOS'),
        _BulletList(
          items: [
            'M-Pesa',
            'E-Mola',
            'Carteira interna DeliGo, quando disponivel',
          ],
        ),
        _Paragraph(
          'Os pagamentos sao processados dentro do fluxo oficial da plataforma e ficam registados no historico do utilizador.',
        ),
        _SectionTitle('2. CONFIRMACAO E LIQUIDACAO'),
        _BulletList(
          items: [
            'O pedido so segue para o fluxo operacional apos confirmacao do pagamento',
            'O restaurante recebe automaticamente apos confirmacao da entrega, conforme as regras internas da plataforma',
            'A DeliGo pode reter temporariamente valores para validacao antifraude, disputa ou reconciliacao',
          ],
        ),
        _SectionTitle('3. TAXAS DA PLATAFORMA'),
        _BulletList(
          items: [
            'Taxa de restaurante: 6% sobre cada pedido concluido',
            'Taxa de entrega: 5%',
            'Taxa de entrega ao cliente: minimo 100 MZN e maximo 200 MZN, variando por zona',
            'Depósitos na carteira: taxa operacional de 3%, mostrada antes da confirmação',
            'Levantamentos da carteira: taxa operacional de 3%, mostrada antes da confirmação',
          ],
        ),
        _SectionTitle('4. GATEWAY DE PAGAMENTOS'),
        _Paragraph(
          'A DeliGo utiliza parceiros de pagamento para depositos, levantamentos e reconciliacoes. As taxas operacionais podem ser atualizadas conforme regras internas e dos parceiros.',
        ),
        _SectionTitle('5. CARTEIRA E TRANSFERÊNCIAS'),
        _Paragraph(
          'Depósitos, levantamentos e transferências entre utilizadores só são concluídos após confirmação no histórico. A operadora é detectada automaticamente pelo número registado. Antes de transferir, o utilizador deve confirmar o número e o nome apresentados; uma transferência confirmada para o destinatário errado pode não ser reversível.',
        ),
        _SectionTitle('6. CASOS ELEGIVEIS PARA REEMBOLSO'),
        _BulletList(
          items: [
            'Pedido nao entregue',
            'Erro comprovado do restaurante',
            'Problemas tecnicos confirmados',
            'Cancelamento dentro do prazo permitido pela plataforma',
            'Cobranca duplicada ou incorreta, mediante validacao',
          ],
        ),
        _SectionTitle('7. CASOS NAO ELEGIVEIS OU PARCIAIS'),
        _BulletList(
          items: [
            'Pedidos ja preparados, recolhidos ou entregues podem nao ter reembolso total',
            'Pedidos com indicios de fraude podem ficar sujeitos a revisao adicional',
            'O valor final do reembolso pode variar de acordo com o estado operacional do pedido no momento do cancelamento',
          ],
        ),
        _SectionTitle('8. FORMA DO REEMBOLSO'),
        _BulletList(
          items: [
            'Carteira interna DeliGo',
            'Metodo de pagamento original, quando tecnicamente possivel',
            'Outro canal operacional definido pela plataforma',
          ],
        ),
        _SectionTitle('9. PRAZOS'),
        _Paragraph(
          'O prazo de processamento depende do metodo utilizado, da confirmacao operacional e da rede de pagamento. Quando disponivel, o estado do reembolso sera mostrado no historico do utilizador.',
        ),
        _SectionTitle('10. DISPUTAS E ANALISE'),
        _Paragraph(
          'A DeliGo pode solicitar provas adicionais, mensagens, registos de entrega e outros elementos para analisar cada caso individualmente e prevenir fraude.',
        ),
        _SectionTitle('11. CONTACTO'),
        _ContactBlock(),
      ],
    );
  }
}

class _LegalScaffold extends StatelessWidget {
  const _LegalScaffold({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: AppColors.primaryRed,
        foregroundColor: AppColors.cleanWhite,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }
}

class _LegalAside extends StatelessWidget {
  const _LegalAside({required this.lastUpdated, required this.country});

  final String lastUpdated;
  final String country;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primaryRed.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.primaryRed.withValues(alpha: 0.18),
        ),
      ),
      child: Text(
        'Ultima atualizacao: $lastUpdated\nAplicavel em: $country',
        style: const TextStyle(
          color: AppColors.darkGray,
          height: 1.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Text(
        text,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _SubSectionTitle extends StatelessWidget {
  const _SubSectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Text(
        text,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _Paragraph extends StatelessWidget {
  const _Paragraph(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          height: 1.55,
          color: AppColors.darkGray,
        ),
      ),
    );
  }
}

class _BulletList extends StatelessWidget {
  const _BulletList({required this.items});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: items
          .map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('- ', style: TextStyle(height: 1.5)),
                  Expanded(
                    child: Text(
                      item,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: AppColors.darkGray,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _ContactBlock extends StatelessWidget {
  const _ContactBlock();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 6, bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Entidade: Deligo Triunfal, LDA',
            style: TextStyle(fontSize: 14, height: 1.5),
          ),
          Text(
            'App: DeliGo',
            style: TextStyle(fontSize: 14, height: 1.5),
          ),
          Text(
            'Email: support@deligo.app',
            style: TextStyle(fontSize: 14, height: 1.5),
          ),
          Text(
            'WhatsApp/Suporte: +258 84 113 0015',
            style: TextStyle(fontSize: 14, height: 1.5),
          ),
        ],
      ),
    );
  }
}
