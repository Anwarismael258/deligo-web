import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import '../../config/theme/app_colors.dart';

class CourierDashboard extends StatefulWidget {
  const CourierDashboard({super.key});

  @override
  State<CourierDashboard> createState() => _CourierDashboardState();
}

class _CourierDashboardState extends State<CourierDashboard> {
  final supabase = Supabase.instance.client;
  int _selectedIndex = 0;
  bool isOnline = false;
  bool isLoading = true;
  String? kycStatus;
  String? rejectionReason;

  @override
  void initState() {
    super.initState();
    _checkKycStatus();
  }

  Future<void> _checkKycStatus() async {
    try {
      final user = supabase.auth.currentUser;
      if (user != null) {
        final response = await supabase
            .from('profiles')
            .select('kyc_status, kyc_rejection_reason')
            .eq('id', user.id)
            .single();

        if (mounted) {
          setState(() {
            kycStatus = response['kyc_status'];
            rejectionReason = response['kyc_rejection_reason'];
            isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> _logout() async {
    try {
      await supabase.auth.signOut();
      if (mounted) {
        context.go('/login');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Nao foi possivel sair agora. Tente novamente.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show loading while checking KYC status
    if (isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // If KYC is not approved, show pending/rejected screen
    if (kycStatus != 'approved') {
      return _buildKycBlockedScreen();
    }

    return _buildMainDashboard();
  }

  Widget _buildKycBlockedScreen() {
    final isRejected = kycStatus == 'rejected';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Deligo - Estafeta'),
        backgroundColor: AppColors.primaryRed,
        foregroundColor: AppColors.cleanWhite,
        actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 40),

            // Icon
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: (isRejected ? Colors.red : Colors.orange).withValues(
                  alpha: 0.1,
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isRejected ? Icons.cancel : Icons.hourglass_empty,
                size: 80,
                color: isRejected ? Colors.red : Colors.orange,
              ),
            ),
            const SizedBox(height: 32),

            // Title
            Text(
              isRejected ? 'KYC Reprovado' : 'KYC Pendente',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppColors.darkGray,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),

            // Message
            if (isRejected && rejectionReason != null) ...[
              Card(
                color: Colors.red.withValues(alpha: 0.1),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.error_outline, color: Colors.red),
                          SizedBox(width: 8),
                          Text(
                            'Motivo da rejeicao:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.red,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        rejectionReason!,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Por favor, envie novamente os documentos KYC corretos.',
                style: TextStyle(fontSize: 16, color: AppColors.neutralGray),
                textAlign: TextAlign.center,
              ),
            ] else ...[
              const Text(
                'A sua conta esta a aguardar aprovacao do KYC.',
                style: TextStyle(fontSize: 16, color: AppColors.neutralGray),
                textAlign: TextAlign.center,
              ),
            ],

            const SizedBox(height: 32),

            // Info Card
            Card(
              color: AppColors.primaryRed.withValues(alpha: 0.1),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.info_outline, color: AppColors.primaryRed),
                        SizedBox(width: 8),
                        Text(
                          'Informacoes',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryRed,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '- Nao pode aceitar entregas enquanto o KYC nao for aprovado.\n'
                      '- O processo pode levar ate 24 horas.\n'
                      '- Recebera uma notificacao quando aprovado.',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[700],
                        height: 1.6,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),

            // Button to check status
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: _checkKycStatus,
                icon: const Icon(Icons.refresh),
                label: const Text('Verificar Novamente'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primaryRed,
                  side: const BorderSide(color: AppColors.primaryRed),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Logout button
            TextButton(
              onPressed: _logout,
              child: const Text(
                'Sair da conta',
                style: TextStyle(color: AppColors.neutralGray),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainDashboard() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Deligo - Estafeta'),
        backgroundColor: AppColors.primaryRed,
        foregroundColor: AppColors.cleanWhite,
        actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          // Home Tab
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Dashboard Estafeta',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        const Text('Status Online'),
                        const SizedBox(height: 16),
                        Switch(
                          value: isOnline,
                          onChanged: (value) =>
                              setState(() => isOnline = value),
                          activeThumbColor: Colors.green,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          isOnline ? 'Voce esta ONLINE' : 'Voce esta OFFLINE',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isOnline ? Colors.green : Colors.red,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              const Text(
                                '0',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text('Entregas'),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              const Text(
                                '0 MZN',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text('Ganho'),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Available Deliveries Tab
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Text(
                  'Entregas Disponiveis',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.local_shipping,
                        size: 64,
                        color: Colors.grey[300],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        isOnline
                            ? 'Nenhuma entrega disponivel'
                            : 'Fique online para receber entregas',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // History Tab
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Text(
                  'Historico de Entregas',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Center(
                  child: Column(
                    children: [
                      Icon(Icons.history, size: 64, color: Colors.grey[300]),
                      const SizedBox(height: 16),
                      const Text('Nenhuma entrega realizada'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        selectedItemColor: AppColors.primaryRed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(
            icon: Icon(Icons.local_shipping),
            label: 'Entregas',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history),
            label: 'Historico',
          ),
        ],
      ),
    );
  }
}






