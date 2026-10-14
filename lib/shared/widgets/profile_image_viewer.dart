import 'package:flutter/material.dart';

class ProfileImageViewer extends StatelessWidget {
  final String? imageUrl;
  final double size;
  final IconData fallbackIcon;
  final Color backgroundColor;
  final Color iconColor;
  final double? radius;

  const ProfileImageViewer({
    super.key,
    required this.imageUrl,
    this.size = 48,
    this.fallbackIcon = Icons.person,
    this.backgroundColor = const Color(0xFFEAE7E1),
    this.iconColor = Colors.grey,
    this.radius,
  });

  @override
  Widget build(BuildContext context) {
    final url = imageUrl?.trim() ?? '';
    final shapeRadius = radius ?? size / 2;
    final avatar = CircleAvatar(
      radius: shapeRadius,
      backgroundColor: backgroundColor,
      backgroundImage: url.isNotEmpty ? NetworkImage(url) : null,
      child: url.isEmpty
          ? Icon(fallbackIcon, color: iconColor, size: size * .48)
          : null,
    );
    if (url.isEmpty) return avatar;
    return GestureDetector(
      onTap: () => showDialog<void>(
        context: context,
        barrierColor: Colors.black87,
        builder: (_) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(12),
          child: Stack(
            alignment: Alignment.topRight,
            children: [
              InteractiveViewer(
                minScale: .8,
                maxScale: 4,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Image.network(url, fit: BoxFit.contain),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                color: Colors.white,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
      ),
      child: avatar,
    );
  }
}
