import 'package:flutter/material.dart';

import '../../../../core/utils/app_theme.dart';

class OdometerCard extends StatelessWidget {
  const OdometerCard({
    super.key,
    required this.startKm,
    required this.endKm,
    this.startPhotoUrl,
    this.endPhotoUrl,
  });

  final double? startKm;
  final double? endKm;
  final String? startPhotoUrl;
  final String? endPhotoUrl;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Odometer', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _OdoTile(label: 'Start', value: startKm, photoUrl: startPhotoUrl),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _OdoTile(label: 'End', value: endKm, photoUrl: endPhotoUrl),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OdoTile extends StatelessWidget {
  const _OdoTile({required this.label, required this.value, this.photoUrl});

  final String label;
  final double? value;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppTheme.textMuted)),
          const SizedBox(height: 6),
          Text(
            value == null ? '—' : '${value!.toStringAsFixed(1)} km',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          _PhotoPreview(url: photoUrl),
        ],
      ),
    );
  }
}

class _PhotoPreview extends StatelessWidget {
  const _PhotoPreview({this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) {
      return Container(
        height: 72,
        decoration: BoxDecoration(
          color: AppTheme.background,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Icon(Icons.image_not_supported, color: AppTheme.textMuted),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        url!,
        height: 72,
        width: double.infinity,
        fit: BoxFit.cover,
      ),
    );
  }
}
