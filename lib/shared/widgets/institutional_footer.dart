import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/theme/app_colors.dart';

class InstitutionalFooter extends StatefulWidget {
  const InstitutionalFooter({super.key});

  @override
  State<InstitutionalFooter> createState() => _InstitutionalFooterState();
}

class _InstitutionalFooterState extends State<InstitutionalFooter> {
  String _version = '...';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() => _version = info.version);
  }

  Future<void> _openInstitutionalSite() async {
    final uri = Uri.parse('https://deligotriunfal.co.mz');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final currentYear = DateTime.now().year;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 18, 8, 8),
      child: Center(
        child: DefaultTextStyle(
          style: const TextStyle(
            color: AppColors.neutralGray,
            fontSize: 12,
            height: 1.35,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'DeliGo',
                style: TextStyle(
                  color: AppColors.darkGray,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text('Versão $_version'),
              TextButton(
                onPressed: _openInstitutionalSite,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primaryRed,
                  minimumSize: Size.zero,
                  padding: EdgeInsets.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('deligotriunfal.co.mz'),
              ),
              Text('© 2025–$currentYear DeliGo Triunfal, Lda.'),
              const Text('Todos os direitos reservados.'),
            ],
          ),
        ),
      ),
    );
  }
}
