import 'package:flutter/material.dart';
import '../../shared/models/payment.dart';
import '../../shared/widgets/deligo_pressable.dart';
import '../../services/payment_service.dart';
import '../../config/theme/app_colors.dart';

class PaymentPage extends StatefulWidget {
  final String orderId;
  final double amount;
  final String baseUrl;

  const PaymentPage({
    super.key,
    required this.orderId,
    required this.amount,
    required this.baseUrl,
  });

  @override
  State<PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends State<PaymentPage> {
  late final PaymentService _paymentService;
  String _selectedMethod = 'mpesa';
  ProviderPayment? _payment;
  bool _loading = false;
  bool _polling = false;
  bool _paymentSheetOpen = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _paymentService = PaymentService();
  }

  Future<void> _createPayment() async {
    if (_loading || _paymentSheetOpen) return;
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final payment = await _paymentService.createPayment(
        orderId: widget.orderId,
        amount: widget.amount,
        walletType: _selectedMethod,
      );

      setState(() {
        _payment = payment;
        _loading = false;
      });

      if (payment == null) {
        throw Exception(
          _paymentService.lastErrorMessage ?? 'Falha ao criar pagamento',
        );
      }
      if (payment.hasQrCode) {
        _showQrCode(payment.qrCode ?? '');
      } else {
        _showPaymentInstructions(payment.paymentInstructions);
      }

      _startPolling(payment.id);
    } catch (e) {
      setState(() {
        _loading = false;
        _errorMessage = e.toString();
      });
    }
  }

  void _startPolling(String paymentId) {
    setState(() => _polling = true);

    Future<void>.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _polling = false);
    });
  }

  void _showQrCode(String qrData) {
    _paymentSheetOpen = true;
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Escaneie e confirme no teu app',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: AppColors.primaryGreen.withValues(alpha: 0.28),
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.glowInteractive,
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.qr_code_2,
                    size: 150,
                    color: AppColors.primaryGreen,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    qrData,
                    style: const TextStyle(fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Abra o M-Pesa ou e-Mola e conclua o pagamento por lá.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.neutralGray),
            ),
            const SizedBox(height: 24),
            if (_polling) const CircularProgressIndicator(),
          ],
        ),
      ),
    ).whenComplete(() {
      _paymentSheetOpen = false;
    });
  }

  void _showPaymentInstructions(String instructions) {
    _paymentSheetOpen = true;
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Siga estes passos',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primaryGreen.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: AppColors.primaryGreen.withValues(alpha: 0.16),
                ),
              ),
              child: Text(
                instructions,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 24),
            if (_polling) ...[
              const Text(
                'Estamos a confirmar o teu pagamento...',
                style: TextStyle(color: AppColors.neutralGray),
              ),
              const SizedBox(height: 16),
              const CircularProgressIndicator(),
            ],
          ],
        ),
      ),
    ).whenComplete(() {
      _paymentSheetOpen = false;
    });
  }

  void _showSuccessAndPop(ProviderPayment payment) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: AppColors.successGreen, size: 32),
            SizedBox(width: 8),
            Text('Pagamento confirmado'),
          ],
        ),
        content: Text(
          'Pagamento de ${payment.amount.toStringAsFixed(0)} MZN confirmado. O pedido foi enviado ao restaurante e aguarda confirmação.',
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              if (_paymentSheetOpen && Navigator.of(this.context).canPop()) {
                Navigator.of(this.context).pop();
              }
              if (Navigator.of(this.context).canPop()) {
                Navigator.of(this.context).pop(true);
              }
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pagamento'),
        backgroundColor: AppColors.primaryRed,
        foregroundColor: AppColors.cleanWhite,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          const Text(
                            'Total a pagar',
                            style: TextStyle(
                              fontSize: 16,
                              color: AppColors.neutralGray,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${widget.amount.toStringAsFixed(0)} MZN',
                            style: const TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primaryRed,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Metodo de pagamento',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  _buildPaymentMethodTile(
                    'M-Pesa',
                    'mpesa',
                    Icons.phone_android,
                  ),
                  const SizedBox(height: 8),
                  _buildPaymentMethodTile('e-Mola', 'emola', Icons.smartphone),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: Colors.red),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _createPayment,
                      child: const Text(
                        'Pagar',
                        style: TextStyle(fontSize: 18),
                      ),
                    ),
                  ),
                  if (_payment != null) ...[
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 16),
                    _buildPaymentStatus(),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildPaymentMethodTile(String title, String value, IconData icon) {
    final isSelected = _selectedMethod == value;
    return DeligoPressable(
      onTap: () => setState(() => _selectedMethod = value),
      borderRadius: BorderRadius.circular(18),
      pressedScale: 0.98,
      splashColor: isSelected
          ? AppColors.accentYellow.withValues(alpha: 0.20)
          : AppColors.rippleBase,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? AppColors.primaryGreen : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(18),
          color: isSelected
              ? AppColors.primaryGreen.withValues(alpha: 0.08)
              : AppColors.cleanWhite,
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.glowInteractive,
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected
                  ? AppColors.primaryGreen
                  : AppColors.neutralGray,
              size: 28,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected
                      ? AppColors.primaryGreen
                      : AppColors.darkGray,
                ),
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle, color: AppColors.primaryGreen),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentStatus() {
    final status = _payment!.status;
    Color statusColor;
    String statusText;
    IconData statusIcon;

    switch (status) {
      case 'paid':
        statusColor = AppColors.successGreen;
        statusText = 'Pago';
        statusIcon = Icons.check_circle;
        break;
      case 'failed':
        statusColor = Colors.red;
        statusText = 'Falhou';
        statusIcon = Icons.error;
        break;
      default:
        statusColor = Colors.orange;
        statusText = 'Pendente';
        statusIcon = Icons.hourglass_empty;
    }

    return Card(
      color: statusColor.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(statusIcon, color: statusColor, size: 32),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Status do pagamento',
                  style: TextStyle(color: AppColors.neutralGray, fontSize: 12),
                ),
                Text(
                  statusText,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
