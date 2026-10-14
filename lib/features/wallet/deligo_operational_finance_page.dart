import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/theme/app_colors.dart';
import '../../services/deligo_operational_finance_service.dart';

class DeligoOperationalFinancePage extends StatefulWidget {
  const DeligoOperationalFinancePage({super.key, required this.beneficiaryType});
  final String beneficiaryType;

  @override
  State<DeligoOperationalFinancePage> createState() =>
      _DeligoOperationalFinancePageState();
}

class _DeligoOperationalFinancePageState extends State<DeligoOperationalFinancePage> {
  final _service = DeligoOperationalFinanceService();
  Map<String, dynamic>? _data;
  RealtimeChannel? _channel;
  bool _loading = true;
  bool _requesting = false;
  String? _error;
  String _period = 'month';

  bool get _isRestaurant => widget.beneficiaryType == 'restaurant';
  String get _title => _isRestaurant ? 'Financeiro do restaurante' : 'Ganhos do estafeta';

  @override
  void initState() {
    super.initState();
    _load();
    _channel = _service.subscribe(
      beneficiaryType: widget.beneficiaryType,
      onChanged: () { if (mounted) _load(silent: true); },
    );
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  DateTime? get _from {
    final now = DateTime.now();
    return switch (_period) {
      'today' => DateTime(now.year, now.month, now.day),
      'week' => now.subtract(const Duration(days: 7)),
      'month' => DateTime(now.year, now.month, 1),
      _ => null,
    };
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() { _loading = true; _error = null; });
    try {
      final data = await _service.load(beneficiaryType: widget.beneficiaryType, from: _from);
      if (mounted) setState(() { _data = data; _error = null; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _error = 'Não foi possível atualizar o extrato operacional.'; _loading = false; });
    }
  }

  double _number(Object? value) => value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
  String _money(Object? value) => 'MZN ${_number(value).toStringAsFixed(2)}';
  String _label(String raw) => raw.replaceAll('_', ' ').trim();

  Future<void> _withdraw() async {
    final available = _number((_data?['summary'] as Map?)?['available_balance']);
    if (available <= 0) { _message('Não existe saldo operacional disponível para levantar.'); return; }
    final controller = TextEditingController(text: available.toStringAsFixed(2));
    final amount = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Solicitar levantamento'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Disponível: ${_money(available)}'),
          const SizedBox(height: 12),
          TextField(controller: controller, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Valor em MZN', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          const Text('O pedido será processado manualmente. Nenhum pagamento é marcado como concluído sem confirmação administrativa.'),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')), FilledButton(onPressed: () => Navigator.pop(context, double.tryParse(controller.text.replaceAll(',', '.'))), child: const Text('Confirmar'))],
      ),
    );
    if (amount == null) return;
    if (amount <= 0 || amount > available) { _message('Indique um valor maior que zero e até ao saldo disponível.'); return; }
    setState(() => _requesting = true);
    try {
      await _service.requestWithdrawal(beneficiaryType: widget.beneficiaryType, amount: amount, reason: 'Pedido iniciado no aplicativo DeliGo');
      await _load(silent: true);
      if (mounted) _message('Pedido registado. O valor está reservado para processamento manual.');
    } catch (_) { if (mounted) _message('Não foi possível criar o pedido. Confirme o saldo e tente novamente.'); }
    if (mounted) setState(() => _requesting = false);
  }

  void _message(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    final summary = Map<String, dynamic>.from((_data?['summary'] as Map?) ?? const {});
    final ledger = List<Map<String, dynamic>>.from(((_data?['ledger'] as List?) ?? const []).whereType<Map>().map(Map<String, dynamic>.from));
    final withdrawals = List<Map<String, dynamic>>.from(((_data?['withdrawals'] as List?) ?? const []).whereType<Map>().map(Map<String, dynamic>.from));
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: _loading ? const Center(child: CircularProgressIndicator()) : _error != null ? Center(child: FilledButton(onPressed: _load, child: const Text('Tentar novamente'))) : RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Text('Dados oficiais do ledger operacional', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6), const Text('A wallet antiga continua separada enquanto a migração é concluída.'),
          const SizedBox(height: 16),
          _balanceCard(summary),
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [for (final p in const [('today','Hoje'),('week','7 dias'),('month','Mês'),('all','Tudo')]) ChoiceChip(label: Text(p.$2), selected: _period == p.$1, onSelected: (_) { setState(() => _period = p.$1); _load(); })]),
          const SizedBox(height: 20),
          Text('Extrato', style: Theme.of(context).textTheme.titleLarge),
          if (ledger.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Text('Ainda não há movimentos operacionais neste período.')),
          ...ledger.map(_ledgerTile),
          const SizedBox(height: 20), Text('Levantamentos', style: Theme.of(context).textTheme.titleLarge),
          if (withdrawals.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text('Nenhum levantamento solicitado.')),
          ...withdrawals.map(_withdrawalTile),
          const SizedBox(height: 24),
          FilledButton.icon(onPressed: _requesting ? null : _withdraw, icon: _requesting ? const SizedBox(height: 18,width: 18,child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.account_balance_outlined), label: Text(_requesting ? 'A registar…' : 'Solicitar levantamento')),
          const SizedBox(height: 12), const Text('Processamento manual: o pedido pode ser aprovado, processado, pago, rejeitado, falhar ou ser cancelado. Nunca será marcado como pago automaticamente.', textAlign: TextAlign.center),
        ]),
      ),
    );
  }

  Widget _balanceCard(Map<String, dynamic> s) {
    final values = <(String, Object?)>[
      ('Bruto', s['gross_total']), ('Comissão', s['commissions_total']),
      ('Líquido', s['net_total']), ('Pendente', s['pending_balance']),
      ('Reservado', s['reserved_balance']), ('Levantado', s['paid_out_total']),
    ];
    return Card(
      color: const Color(0xFF14213D),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Saldo disponível', style: TextStyle(color: Colors.white70)),
          Text(_money(s['available_balance']), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 30)),
          const Divider(color: Colors.white24),
          Wrap(spacing: 18, runSpacing: 10, children: values.map((e) => SizedBox(
            width: 125,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.$1, style: const TextStyle(color: Colors.white70)),
              Text(_money(e.$2), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ]),
          )).toList()),
        ]),
      ),
    );
  }

  Widget _ledgerTile(Map<String, dynamic> row) => Card(child: ListTile(leading: const Icon(Icons.receipt_long_outlined, color: AppColors.primaryRed), title: Text(_label('${row['movement_type'] ?? 'movimento'}')), subtitle: Text('${row['created_at'] ?? ''}\n${row['external_reference'] ?? row['order_id'] ?? 'Sem referência'}'), isThreeLine: true, trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children:[Text(_money(row['net_amount']),style: const TextStyle(fontWeight: FontWeight.w800)),Text(_label('${row['status'] ?? ''}'),style: const TextStyle(fontSize: 11))])));
  Widget _withdrawalTile(Map<String, dynamic> row) => Card(child: ListTile(leading: const Icon(Icons.account_balance_outlined), title: Text(_money(row['amount'])), subtitle: Text('Solicitado: ${row['requested_at'] ?? ''}\n${row['external_reference'] ?? 'Processamento manual'}'), isThreeLine: true, trailing: Chip(label: Text(_label('${row['status'] ?? 'requested'}')))));
}
