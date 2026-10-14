import 'package:flutter/material.dart';

import '../../config/theme/app_colors.dart';

class TermsPage extends StatelessWidget {
  const TermsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Termos e Condições'),
        backgroundColor: AppColors.primaryRed,
        foregroundColor: AppColors.cleanWhite,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            _LegalAside(
              lastUpdated: '19 de Setembro de 2026 · Versão 1.0',
              country: 'República de Moçambique',
            ),
            SizedBox(height: 16),
            Text(
              'DeliGo — Termos e Condições de Utilização',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
            ),
            SizedBox(height: 20),
            _SectionTitle('1. SOBRE A PLATAFORMA'),
            _Paragraph(
              'A DeliGo Entregas e uma plataforma digital de intermediacao de pedidos de comida, ligando clientes, restaurantes parceiros e estafetas independentes.',
            ),
            _Paragraph(
              'Estes termos aplicam-se aos perfis Cliente, Restaurante e Estafeta. A entidade responsável é a DeliGo Triunfal, Lda., com actividade em Maputo, Moçambique. O documento deve ser validado juridicamente antes da publicação definitiva.',
            ),
            _Paragraph(
              'A plataforma atua como intermediadora tecnologica e nao e proprietaria dos produtos comercializados pelos restaurantes.',
            ),
            _SectionTitle('2. ACEITACAO DOS TERMOS'),
            _BulletList(
              items: [
                'Leu integralmente estes Termos',
                'Compreendeu as condicoes',
                'Concorda com as regras estabelecidas',
                'Tem capacidade legal para contratar',
              ],
            ),
            _Paragraph(
              'O uso continuo da plataforma implica aceitacao automatica de futuras atualizacoes.',
            ),
            _SectionTitle('3. ELEGIBILIDADE'),
            _BulletList(
              items: [
                'Ter pelo menos 18 anos',
                'Fornecer informacoes verdadeiras e atualizadas',
                'Possuir numero de telefone valido em Mocambique',
                'Cumprir o processo de verificacao, incluindo KYC quando aplicavel',
              ],
            ),
            _SectionTitle('4. FUNCIONAMENTO DO SERVICO'),
            _SubSectionTitle('4.1 Clientes'),
            _BulletList(
              items: [
                'Visualizar restaurantes e menus',
                'Realizar pedidos',
                'Efetuar pagamento via M-Pesa ou e-Mola',
                'Acompanhar o pedido em tempo real',
                'Confirmar o recebimento',
              ],
            ),
            _Paragraph(
              'O pagamento so e liberado apos a confirmacao da entrega ou recolha.',
            ),
            _SubSectionTitle('4.2 Estafetas'),
            _BulletList(
              items: [
                'Atuam como prestadores de servico independentes',
                'Devem concluir o processo obrigatorio de KYC',
                'Sao responsaveis pela integridade da entrega',
                'Devem manter um nivel minimo aceitavel de avaliacao',
              ],
            ),
            _Paragraph(
              'A DeliGo pode suspender contas por conduta inadequada, fraude ou incumprimento das regras da plataforma.',
            ),
            _SubSectionTitle('4.3 Restaurantes'),
            _BulletList(
              items: [
                'Sao responsaveis pela qualidade dos produtos vendidos',
                'Definem precos e disponibilidade',
                'Devem cumprir os prazos operacionais',
                'Recebem pagamentos apos a confirmacao do pedido ou da entrega, conforme o fluxo aplicavel',
              ],
            ),
            _SectionTitle('5. TAXAS, ENTREGAS E PAGAMENTOS'),
            _SubSectionTitle('5.1 Taxas da plataforma'),
            _BulletList(
              items: [
                'Taxa do restaurante: 6% sobre cada pedido concluido',
                'Taxa de entrega: 5%',
              ],
            ),
            _SubSectionTitle('5.2 Valor de entrega'),
            _BulletList(
              items: [
                'Minimo: 100 MZN',
                'Maximo: 200 MZN',
                'O valor pode variar conforme a zona, distancia e contexto operacional',
              ],
            ),
            _SubSectionTitle('5.3 Carteira e taxas operacionais'),
            _BulletList(
              items: [
                'Depósito na carteira: 3%, mostrado antes da confirmação',
                'Levantamento da carteira: 3%, mostrado antes da confirmação',
                'Uma operação pendente só é concluída quando aparecer como confirmada no histórico',
                'Transferências entre utilizadores exigem validação do número e do nome apresentados',
              ],
            ),
            _SubSectionTitle('5.4 Meios de pagamento'),
            _BulletList(items: ['Pagamentos processados via M-Pesa e e-Mola']),
            _Paragraph(
              'As taxas podem ser atualizadas com aviso previo. Os reembolsos seguem a politica interna da plataforma.',
            ),
            _SectionTitle('6. POLITICA DE REEMBOLSOS'),
            _BulletList(
              items: [
                'Pedido nao entregue',
                'Erro comprovado do restaurante',
                'Problemas tecnicos confirmados',
                'Cancelamento dentro do prazo permitido',
              ],
            ),
            _Paragraph(
              'A DeliGo reserva-se o direito de analisar cada caso individualmente antes de concluir qualquer reembolso.',
            ),
            _SectionTitle('7. RESPONSABILIDADES'),
            _SubSectionTitle('Cliente'),
            _BulletList(
              items: [
                'Informar o endereco correto',
                'Confirmar o recebimento apenas apos a entrega real',
                'Nao praticar fraude ou abuso da plataforma',
              ],
            ),
            _SubSectionTitle('Estafeta'),
            _BulletList(
              items: [
                'Cumprir prazos',
                'Manter postura profissional',
                'Respeitar as regras de transito',
              ],
            ),
            _SubSectionTitle('Restaurante'),
            _BulletList(
              items: [
                'Garantir higiene e qualidade',
                'Cumprir os prazos operacionais',
              ],
            ),
            _SubSectionTitle('Plataforma'),
            _BulletList(
              items: [
                'Garantir seguranca tecnologica',
                'Processar pagamentos corretamente',
                'Disponibilizar canais de suporte',
              ],
            ),
            _SectionTitle('8. CONDUTA PROIBIDA'),
            _BulletList(
              items: [
                'Uso fraudulento da plataforma',
                'Criacao de multiplas contas para manipulacao',
                'Cancelamentos abusivos',
                'Tentativas de manipulacao do sistema financeiro',
              ],
            ),
            _Paragraph(
              'Contas podem ser suspensas sem aviso previo quando houver risco operacional, fraude ou violacao grave destes termos.',
            ),
            _SectionTitle('9. PROTECAO DE DADOS'),
            _BulletList(
              items: [
                'Proteger dados pessoais',
                'Utilizar criptografia e boas praticas de seguranca',
                'Nao vender dados a terceiros sem base legal',
                'Usar informacoes apenas para o funcionamento da plataforma e obrigacoes legais',
              ],
            ),
            _SectionTitle('10. LIMITACAO DE RESPONSABILIDADE'),
            _BulletList(
              items: [
                'Atrasos causados por fatores externos',
                'Problemas de qualidade dos alimentos',
                'Acoes individuais de estafetas ou restaurantes',
              ],
            ),
            _SectionTitle('11. CANCELAMENTO E SUSPENSAO'),
            _BulletList(
              items: [
                'A conta pode ser suspensa por violacao destes termos',
                'Pode ser cancelada pelo proprio utilizador a qualquer momento',
                'Pode ser encerrada pela plataforma por razoes legais ou operacionais',
              ],
            ),
            _SectionTitle('12. ALTERACOES DOS TERMOS'),
            _Paragraph(
              'A DeliGo pode atualizar estes termos a qualquer momento. O uso continuo da plataforma apos alteracoes significa aceitacao automatica.',
            ),
            _SectionTitle('13. LEGISLACAO APLICAVEL'),
            _Paragraph(
              'Estes termos sao regidos pelas leis da Republica de Mocambique.',
            ),
            _SectionTitle('14. CONTACTOS OFICIAIS'),
            _SectionTitle('15. SUPORTE, DISPUTAS E KYC'),
            _Paragraph(
              'Restaurantes e estafetas devem concluir o KYC e manter os documentos válidos. Reclamações devem ser abertas pelo pedido ou chat de suporte, com o número da operação e os comprovativos disponíveis. A DeliGo pode analisar mensagens, localização, comprovativos e histórico para resolver o caso.',
            ),
            _ContactBlock(),
          ],
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
        border: Border.all(color: AppColors.primaryRed.withValues(alpha: 0.18)),
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
      padding: EdgeInsets.only(top: 6, bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Email: deligoentregas@gmail.com',
            style: TextStyle(fontSize: 14, height: 1.5),
          ),
          Text(
            'WhatsApp / Suporte: +258 84 113 0015',
            style: TextStyle(fontSize: 14, height: 1.5),
          ),
        ],
      ),
    );
  }
}
