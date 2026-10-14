import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/router/app_router.dart';
import '../../config/theme/app_colors.dart';
import '../../services/kyc_service.dart';
import '../../services/notification_dispatch_service.dart';
import '../../services/push_notification_service.dart';
import '../../services/sound_controller.dart';

class KycPendingPage extends StatefulWidget {
  const KycPendingPage({super.key});

  @override
  State<KycPendingPage> createState() => _KycPendingPageState();
}

class _KycPendingPageState extends State<KycPendingPage> {
  final supabase = Supabase.instance.client;
  final ImagePicker _picker = ImagePicker();
  final NotificationDispatchService _notificationDispatch =
      NotificationDispatchService.instance;

  Map<String, dynamic>? profile;
  bool isLoading = true;
  bool _isResubmitting = false;
  bool _pendingAfterSubmit = false;
  Timer? _pollingTimer;
  RealtimeChannel? _profileChannel;

  XFile? _restaurantStorePhoto;
  XFile? _restaurantNuitPhoto;
  XFile? _restaurantInteriorPhoto;
  XFile? _biFront;
  XFile? _biBack;
  XFile? _selfie;
  XFile? _courierPhoto;
  XFile? _courierVehiclePhoto;
  XFile? _courierPlatePhoto;
  XFile? _courierLicensePhoto;
  XFile? _courierVehicleDocPhoto;
  XFile? _courierSelfieVehicle;
  XFile? _courierBiFront;
  XFile? _courierBiBack;

  bool get _isRestaurant => profile?['role'] == 'restaurant';
  bool get _isCourier => profile?['role'] == 'courier';
  bool get _needsEmailConfirmation => false;
  bool get _hasUploadedDocs {
    final docs = profile?['kyc_docs'];
    final hasDocs = docs is Map && docs.isNotEmpty;
    return hasDocs || _pendingAfterSubmit;
  }

  String get _roleLabel => _isRestaurant ? 'restaurante' : 'estafeta';

  @override
  void initState() {
    super.initState();
    unawaited(PushNotificationService().registerFcmToken());
    _checkKycStatus();
    _startPolling();
    _subscribeToProfileChanges();
  }

  void _startPolling() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      _checkKycStatus();
    });
  }

  Future<void> _subscribeToProfileChanges() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    await _profileChannel?.unsubscribe();
    _profileChannel = supabase.channel('approval-status-$userId');
    _profileChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'profiles',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: userId,
          ),
          callback: (_) {
            _checkKycStatus();
          },
        )
        .subscribe();
  }

  Future<void> _checkKycStatus() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;
      AppRouter.invalidateProfileCache(user.id);
      final response = await supabase
          .from('profiles')
          .select(
            'id, role, full_name, kyc_status, kyc_rejection_reason, kyc_docs',
          )
          .eq('id', user.id)
          .single();
      AppRouter.primeProfileCache(user.id, Map<String, dynamic>.from(response));

      if (!mounted) return;
      final oldStatus = profile?['kyc_status'];
      final newStatus = response['kyc_status'] as String?;

      final docs = response['kyc_docs'];
      final hasDocs = docs is Map && docs.isNotEmpty;
      setState(() {
        profile = response;
        isLoading = false;
        if (newStatus == 'approved' || newStatus == 'rejected' || hasDocs) {
          _pendingAfterSubmit = false;
        }
      });

        if (newStatus == 'approved' && oldStatus != 'approved') {
          await SoundController.instance.success();
          _showStatusDialog(
            title: 'Conta aprovada!',
            message: _isRestaurant
                ? 'Os documentos do restaurante foram aprovados. Ja pode entrar no painel.'
                : 'Os seus documentos foram aprovados. Ja pode iniciar as entregas.',
            isApproved: true,
          );
        } else if (newStatus == 'rejected' && oldStatus != 'rejected') {
          await SoundController.instance.error();
          final reason =
            response['kyc_rejection_reason'] as String? ?? 'Nao especificado';
          _showStatusDialog(
          title: 'Conta rejeitada',
          message: 'Motivo: $reason',
          isApproved: false,
        );
      } else if (newStatus == 'approved') {
        context.go(
          AppRouter.dashboardForRole(profile?['role']?.toString() ?? 'client'),
        );
      }
    } catch (_) {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _showStatusDialog({
    required String title,
    required String message,
    required bool isApproved,
  }) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          isApproved ? Icons.check_circle : Icons.cancel,
          color: isApproved ? AppColors.successGreen : AppColors.alertRed,
          size: 48,
        ),
        title: Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        content: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, color: AppColors.neutralGray),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (isApproved) {
                context.go(
                  AppRouter.dashboardForRole(
                    profile?['role']?.toString() ?? 'client',
                  ),
                );
              }
            },
            child: Text(
              isApproved ? 'Entrar agora' : 'Fechar',
              style: TextStyle(
                color: isApproved ? AppColors.successGreen : AppColors.alertRed,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (!isApproved)
            TextButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _openSupportChat();
              },
              icon: const Icon(Icons.support_agent),
              label: const Text('Suporte'),
            ),
        ],
      ),
    );
  }

  Future<void> _pickDocument(String type) async {
    final useCamera = type == 'selfie' ||
        type == 'courierSelfie' ||
        type == 'courierSelfieVehicle';
    final file = await _picker.pickImage(
      source: useCamera ? ImageSource.camera : ImageSource.gallery,
    );
    if (file == null || !mounted) return;
    setState(() {
      switch (type) {
        case 'restaurantStorePhoto':
          _restaurantStorePhoto = file;
          break;
        case 'restaurantNuitPhoto':
          _restaurantNuitPhoto = file;
          break;
        case 'restaurantInteriorPhoto':
          _restaurantInteriorPhoto = file;
          break;
        case 'biFront':
          _biFront = file;
          break;
        case 'biBack':
          _biBack = file;
          break;
        case 'selfie':
          _selfie = file;
          break;
        case 'courierPhoto':
          _courierPhoto = file;
          break;
        case 'courierVehiclePhoto':
          _courierVehiclePhoto = file;
          break;
        case 'courierPlatePhoto':
          _courierPlatePhoto = file;
          break;
        case 'courierLicensePhoto':
          _courierLicensePhoto = file;
          break;
        case 'courierVehicleDocPhoto':
          _courierVehicleDocPhoto = file;
          break;
        case 'courierSelfieVehicle':
          _courierSelfieVehicle = file;
          break;
        case 'courierBiFront':
          _courierBiFront = file;
          break;
        case 'courierBiBack':
          _courierBiBack = file;
          break;
      }
    });
  }

  Future<void> _resubmitDocuments() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null || profile == null) return;

    if (_isRestaurant &&
        (_restaurantStorePhoto == null ||
            _restaurantNuitPhoto == null ||
            _restaurantInteriorPhoto == null ||
            _biFront == null ||
            _biBack == null ||
            _selfie == null)) {
      _showSnack(
        'Selecione foto da loja, NUIT, interior, BI frente, BI verso e selfie.',
      );
      return;
    }
    if (_isCourier &&
        (_courierPhoto == null ||
            _courierVehiclePhoto == null ||
            _courierPlatePhoto == null ||
            _courierLicensePhoto == null ||
            _courierVehicleDocPhoto == null ||
            _courierSelfieVehicle == null ||
            _courierBiFront == null ||
            _courierBiBack == null)) {
      _showSnack(
        'Selecione foto do estafeta, BI frente, BI verso, veiculo, matricula, carta, documento do veiculo e selfie com veiculo.',
      );
      return;
    }

    setState(() => _isResubmitting = true);
    try {
      final kycService = KycService(supabase);
      if (_isRestaurant) {
        await kycService.uploadAndSubmitKyc(
          subjectType: 'restaurant',
          subjectName: profile?['full_name']?.toString() ?? '',
          files: {
            'foto_loja': _restaurantStorePhoto!,
            'foto_nuit': _restaurantNuitPhoto!,
            'foto_interior': _restaurantInteriorPhoto!,
            'bi_frente': _biFront!,
            'bi_tras': _biBack!,
            'selfie': _selfie!,
          },
          metadata: {'source': 'kyc_pending_page', 'resubmission': true},
        );
      } else if (_isCourier) {
        await kycService.uploadAndSubmitKyc(
          subjectType: 'courier',
          subjectName: profile?['full_name']?.toString() ?? '',
          files: {
            'foto': _courierPhoto!,
            'bi_frente': _courierBiFront!,
            'bi_tras': _courierBiBack!,
            'foto_veiculo': _courierVehiclePhoto!,
            'foto_matricula': _courierPlatePhoto!,
            'carta_conducao': _courierLicensePhoto!,
            'documento_veiculo': _courierVehicleDocPhoto!,
            'selfie_veiculo': _courierSelfieVehicle!,
          },
          metadata: {'source': 'kyc_pending_page', 'resubmission': true},
        );
      }

      final role = profile?['role']?.toString();
      final fullName = profile?['full_name']?.toString() ?? '';
      final reviewPayload = {
        'user_id': userId,
        'role': role,
        'full_name': fullName,
      };
      for (final targetRole in const ['admin', 'field_agent']) {
        await _notificationDispatch.sendToRole(
          targetRole: targetRole,
          type: 'KYC_RESUBMITTED',
          title: 'KYC reenviado para revisao',
          body:
              '${role == 'restaurant' ? 'Restaurante' : 'Estafeta'} $fullName reenviou os documentos. Ja pode entrar na fila de analise.',
          action: 'OPEN_KYC_REVIEW',
          entityId: userId,
          priority: 'HIGH',
          channel: 'admin_kyc',
          data: reviewPayload,
          metadata: reviewPayload,
        );
      }

      if (!mounted) return;
      setState(() {
        _restaurantStorePhoto = null;
        _restaurantNuitPhoto = null;
        _restaurantInteriorPhoto = null;
        _biFront = null;
        _biBack = null;
        _selfie = null;
        _courierPhoto = null;
        _courierVehiclePhoto = null;
        _courierPlatePhoto = null;
        _courierLicensePhoto = null;
        _courierVehicleDocPhoto = null;
        _courierSelfieVehicle = null;
        _courierBiFront = null;
        _courierBiBack = null;
        _pendingAfterSubmit = true;
      });
      _showSnack(
        'Documentos reenviados. A conta voltou para analise.',
        success: true,
      );
      await _checkKycStatus();
    } catch (e) {
      final message = e.toString().replaceFirst('Exception: ', '').trim();
      if (message.toLowerCase().contains('documentos invalidos')) {
        _showSnack(
          'Documentos invalidos. Verifique as imagens e tente novamente.',
        );
      } else {
        _showSnack(
          message.isEmpty
              ? 'Nao conseguimos reenviar os documentos agora.'
              : message,
        );
      }
    } finally {
      if (mounted) setState(() => _isResubmitting = false);
    }
  }

  void _showSnack(String message, {bool success = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: success
            ? AppColors.successGreen
            : AppColors.primaryRed,
      ),
    );
  }

  void _openSupportChat() {
    final role = profile?['role']?.toString().trim();
    if (role != null && role.isNotEmpty) {
      context.push('/support/$role');
      return;
    }
    context.push('/support');
  }

  Future<void> _logout() async {
    _pollingTimer?.cancel();
    await _profileChannel?.unsubscribe();
    try {
      AuthRefreshNotifier.markIntentionalSignOut();
      await supabase.auth.signOut();
      if (mounted) context.go('/login');
    } catch (_) {
      _showSnack('Nao conseguimos sair agora. Tente novamente.');
    }
  }

  Widget _docButton(String label, XFile? file, String type) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: OutlinedButton.icon(
        onPressed: _isResubmitting ? null : () => _pickDocument(type),
        icon: Icon(file == null ? Icons.upload_file : Icons.check_circle),
        label: Text(file == null ? label : '$label pronto'),
      ),
    );
  }

  Widget _buildDocumentSubmissionState({required bool rejected}) {
    final reason = profile?['kyc_rejection_reason']?.toString().trim();
    return Column(
      children: [
        Icon(
          rejected ? Icons.cancel_outlined : Icons.file_open_outlined,
          size: 72,
          color: rejected ? AppColors.alertRed : AppColors.primaryRed,
        ),
        const SizedBox(height: 20),
        Text(
          rejected ? 'Documentos precisam de ajuste' : 'Concluir onboarding',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Text(
          rejected
              ? (reason?.isNotEmpty == true
                    ? 'Motivo: $reason'
                    : 'Os documentos foram rejeitados.')
              : 'A sua conta ja foi criada. Falta enviar os documentos para iniciar a verificacao.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 15, color: AppColors.neutralGray),
        ),
        const SizedBox(height: 24),
        if (rejected) ...[
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _openSupportChat,
              icon: const Icon(Icons.support_agent),
              label: const Text('Falar com o suporte'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primaryRed,
                side: const BorderSide(color: AppColors.primaryRed),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            _isRestaurant
                ? 'Documentos do restaurante'
                : 'Documentos do estafeta',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 12),
        if (_isRestaurant) ...[
          _docButton(
            'Foto da loja',
            _restaurantStorePhoto,
            'restaurantStorePhoto',
          ),
          _docButton('Foto do NUIT', _restaurantNuitPhoto, 'restaurantNuitPhoto'),
          _docButton(
            'Foto do interior',
            _restaurantInteriorPhoto,
            'restaurantInteriorPhoto',
          ),
          _docButton('BI frente', _biFront, 'biFront'),
          _docButton('BI verso', _biBack, 'biBack'),
          _docButton('Selfie com rosto visivel', _selfie, 'selfie'),
        ] else if (_isCourier) ...[
          _docButton('Foto do estafeta', _courierPhoto, 'courierPhoto'),
          _docButton('BI frente', _courierBiFront, 'courierBiFront'),
          _docButton('BI verso', _courierBiBack, 'courierBiBack'),
          _docButton(
            'Foto do veiculo',
            _courierVehiclePhoto,
            'courierVehiclePhoto',
          ),
          _docButton(
            'Foto da matricula/placa',
            _courierPlatePhoto,
            'courierPlatePhoto',
          ),
          _docButton(
            'Carta de conducao',
            _courierLicensePhoto,
            'courierLicensePhoto',
          ),
          _docButton(
            'Documento do veiculo',
            _courierVehicleDocPhoto,
            'courierVehicleDocPhoto',
          ),
          _docButton(
            'Foto do estafeta com o veiculo',
            _courierSelfieVehicle,
            'courierSelfieVehicle',
          ),
        ],
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isResubmitting ? null : _resubmitDocuments,
            icon: _isResubmitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            label: Text(
              _isResubmitting
                  ? (rejected ? 'A reenviar...' : 'A enviar...')
                  : (rejected ? 'Reenviar documentos' : 'Enviar documentos'),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryRed,
              foregroundColor: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _profileChannel?.unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = profile?['kyc_status']?.toString() ?? 'pending';
    final needsDocumentSubmission =
        status == 'pending' &&
        !_hasUploadedDocs &&
        (_isRestaurant || _isCourier);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isRestaurant ? 'Analise do restaurante' : 'Verificacao KYC',
        ),
        backgroundColor: AppColors.primaryRed,
        foregroundColor: AppColors.cleanWhite,
        actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _checkKycStatus,
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  const SizedBox(height: 20),
                  if (status == 'rejected' || needsDocumentSubmission)
                    _buildDocumentSubmissionState(
                      rejected: status == 'rejected',
                    )
                  else
                    _OnboardingStatusCard(
                      roleLabel: _roleLabel,
                      statusLabel: _getStatusText(status),
                      hasUploadedDocs: _hasUploadedDocs,
                      approved: status == 'approved',
                      needsEmailConfirmation: _needsEmailConfirmation,
                    ),
                  const SizedBox(height: 28),
                  OutlinedButton.icon(
                    onPressed: _checkKycStatus,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Verificar novamente'),
                  ),
                  if (status == 'rejected') ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _openSupportChat,
                      icon: const Icon(Icons.support_agent),
                      label: const Text('Abrir suporte'),
                    ),
                  ],
                  const SizedBox(height: 12),
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

  String _getStatusText(String status) {
    switch (status) {
      case 'approved':
        return 'Aprovado';
      case 'rejected':
        return 'Rejeitado';
      default:
        return _hasUploadedDocs ? 'Em analise' : 'Aguardando documentos';
    }
  }
}

class _OnboardingStatusCard extends StatelessWidget {
  const _OnboardingStatusCard({
    required this.roleLabel,
    required this.statusLabel,
    required this.hasUploadedDocs,
    required this.approved,
    required this.needsEmailConfirmation,
  });

  final String roleLabel;
  final String statusLabel;
  final bool hasUploadedDocs;
  final bool approved;
  final bool needsEmailConfirmation;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.85, end: 1),
          duration: const Duration(milliseconds: 1100),
          curve: Curves.easeInOut,
          builder: (context, value, child) =>
              Transform.scale(scale: value, child: child),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.hourglass_top_rounded,
              size: 80,
              color: Colors.orange,
            ),
          ),
        ),
        const SizedBox(height: 28),
        Text(
          roleLabel == 'restaurante'
              ? 'Onboarding do restaurante'
              : 'Onboarding do estafeta',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 14),
        const Text(
          'A conta ja foi criada. Agora estamos a acompanhar os passos finais para ativar o acesso completo.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            color: AppColors.neutralGray,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Status: $statusLabel',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange,
                  ),
                ),
                const SizedBox(height: 12),
                const _ProgressStep(
                  done: true,
                  title: 'Conta criada',
                  subtitle: 'O registo inicial ja ficou concluido.',
                ),
                _ProgressStep(
                  done: hasUploadedDocs,
                  title: 'Documentos enviados',
                  subtitle: hasUploadedDocs
                      ? 'Recebemos os ficheiros e eles estao em validacao.'
                      : 'Ainda falta enviar os documentos obrigatorios.',
                ),
                _ProgressStep(
                  done: approved,
                  active: !approved && hasUploadedDocs,
                  title: 'Revisao da equipa',
                  subtitle: approved
                      ? 'A verificacao documental foi concluida.'
                      : 'Estamos a rever os dados enviados.',
                ),
                _ProgressStep(
                  done: approved && !needsEmailConfirmation,
                  active: needsEmailConfirmation,
                  title: 'Ativacao final',
                  subtitle: needsEmailConfirmation
                      ? 'Falta confirmar o email para liberar o acesso total.'
                      : approved
                      ? 'Conta pronta para uso.'
                      : 'Vai ser liberada assim que a revisao terminar.',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Card(
          color: AppColors.primaryRed.withValues(alpha: 0.08),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.info_outline, color: AppColors.primaryRed),
                    const SizedBox(width: 8),
                    Text(
                      'Proximo passo do $roleLabel',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryRed,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  hasUploadedDocs
                      ? 'Os documentos ja foram recebidos. Assim que a revisao terminar, este ecran sera atualizado automaticamente.'
                      : 'Envie os documentos para iniciar a revisao. Depois disso, o estado vai mudar automaticamente aqui.',
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.neutralGray,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ProgressStep extends StatelessWidget {
  const _ProgressStep({
    required this.done,
    required this.title,
    required this.subtitle,
    this.active = false,
  });

  final bool done;
  final bool active;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final color = done
        ? AppColors.successGreen
        : active
        ? Colors.orange
        : AppColors.neutralGray;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              done
                  ? Icons.check_circle
                  : active
                  ? Icons.hourglass_top_rounded
                  : Icons.radio_button_unchecked,
              color: color,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontWeight: FontWeight.bold, color: color),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(color: AppColors.neutralGray),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
