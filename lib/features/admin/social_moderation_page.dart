import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/theme/app_colors.dart';

class SocialModerationPage extends StatefulWidget {
  const SocialModerationPage({super.key});

  @override
  State<SocialModerationPage> createState() => _SocialModerationPageState();
}

class _SocialModerationPageState extends State<SocialModerationPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _reports = const [];
  bool _loading = true;
  String _filter = 'open';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      var query = _supabase.from('social_review_reports').select('*');
      final rows = _filter == 'all'
          ? await query.order('created_at', ascending: false)
          : await query
                .eq('status', _filter)
                .order('created_at', ascending: false);
      if (!mounted) return;
      setState(() {
        _reports = (rows as List).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setStatus(String id, String status) async {
    await _supabase
        .from('social_review_reports')
        .update({'status': status})
        .eq('id', id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Moderacao social')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'open', label: Text('Abertas')),
                ButtonSegment(value: 'reviewing', label: Text('Em analise')),
                ButtonSegment(value: 'all', label: Text('Todas')),
              ],
              selected: {_filter},
              onSelectionChanged: (value) {
                setState(() => _filter = value.first);
                _load();
              },
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _reports.isEmpty
                ? const Center(child: Text('Sem denuncias neste filtro.'))
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _reports.length,
                      itemBuilder: (context, index) {
                        final report = _reports[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.flag_rounded,
                                      color: AppColors.primaryRed,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '${report['review_type']} - ${report['status']}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(report['reason']?.toString() ?? ''),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    OutlinedButton(
                                      onPressed: () => _setStatus(
                                        report['id'].toString(),
                                        'reviewing',
                                      ),
                                      child: const Text('Analisar'),
                                    ),
                                    FilledButton(
                                      onPressed: () => _setStatus(
                                        report['id'].toString(),
                                        'resolved',
                                      ),
                                      child: const Text('Resolver'),
                                    ),
                                    TextButton(
                                      onPressed: () => _setStatus(
                                        report['id'].toString(),
                                        'dismissed',
                                      ),
                                      child: const Text('Descartar'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
