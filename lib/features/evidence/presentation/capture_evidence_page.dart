import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive/hive.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/utils/logger.dart';
import '../../../ui_kit/models/enums.dart';
import '../../../ui_kit/theme/app_colors.dart';
import '../../../ui_kit/theme/app_spacing.dart';
import '../../../ui_kit/widgets/badges.dart';
import '../../../ui_kit/widgets/buttons.dart';
import '../../../ui_kit/widgets/cards.dart';
import '../../../ui_kit/widgets/forms.dart';
import '../../../ui_kit/widgets/navigation.dart';
import '../../offline/hive_boxes.dart';
import '../../trips/data/trips_repository.dart';

class CaptureEvidencePage extends ConsumerStatefulWidget {
  const CaptureEvidencePage({super.key, required this.tripId});

  final int tripId;

  @override
  ConsumerState<CaptureEvidencePage> createState() => _CaptureEvidencePageState();
}

class _CaptureEvidencePageState extends ConsumerState<CaptureEvidencePage> {
  final _picker = ImagePicker();
  bool _loading = true;
  bool _saving = false;

  late final List<_EvidenceSectionState> _sections = [
    _EvidenceSectionState(
      type: _EvidenceSectionType.deliveryArrival,
      noteController: TextEditingController(),
    ),
    _EvidenceSectionState(
      type: _EvidenceSectionType.sealVerification,
      noteController: TextEditingController(),
    ),
    _EvidenceSectionState(
      type: _EvidenceSectionType.damageReport,
      noteController: TextEditingController(),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadExistingEvidence();
  }

  @override
  void dispose() {
    for (final section in _sections) {
      section.noteController.dispose();
    }
    super.dispose();
  }

  Future<void> _loadExistingEvidence() async {
    setState(() => _loading = true);
    try {
      final evidence = await ref
          .read(tripsRepositoryProvider)
          .fetchTripEvidence(widget.tripId);
      for (final item in evidence) {
        final kind = item['kind']?.toString() ?? '';
        final section = _sectionForKind(kind);
        if (section == null) continue;
        final url =
            item['photo_url']?.toString() ??
            item['photo']?.toString() ??
            item['file_url']?.toString() ??
            item['url']?.toString();
        if (url == null || url.isEmpty) continue;
        section.photos.add(
          _EvidencePhoto(
            type: section.type,
            remoteUrl: url,
            note: item['note']?.toString() ?? '',
            lat: _toDouble(item['lat']),
            lng: _toDouble(item['lng']),
            timestamp:
                DateTime.tryParse(item['recorded_at']?.toString() ?? '') ??
                DateTime.tryParse(item['captured_at']?.toString() ?? '') ??
                DateTime.now(),
            status: _EvidenceUploadStatus.synced,
          ),
        );
      }

      final queue = Hive.box<Map>(HiveBoxes.evidenceQueue);
      for (final raw in queue.values) {
        if (raw['trip_id'] != widget.tripId || raw['type'] != 'evidence') {
          continue;
        }
        final path = raw['photo_path']?.toString();
        final kind = raw['kind']?.toString() ?? '';
        final section = _sectionForKind(kind);
        if (path == null || path.isEmpty || section == null) continue;
        section.photos.add(
          _EvidencePhoto(
            type: section.type,
            localPath: path,
            note: raw['note']?.toString() ?? '',
            lat: _toDouble(raw['lat']),
            lng: _toDouble(raw['lng']),
            timestamp:
                DateTime.tryParse(raw['recorded_at']?.toString() ?? '') ??
                DateTime.now(),
            status: _EvidenceUploadStatus.queued,
          ),
        );
      }
    } catch (e, st) {
      Logger.e('Evidence preload failed', e, st);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load evidence: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  _EvidenceSectionState? _sectionForKind(String kind) {
    switch (kind) {
      case 'arrival':
      case 'delivery_arrival':
        return _sections.firstWhere(
          (s) => s.type == _EvidenceSectionType.deliveryArrival,
        );
      case 'seal_verification':
      case 'offloading':
        return _sections.firstWhere(
          (s) => s.type == _EvidenceSectionType.sealVerification,
        );
      case 'damage_report':
      case 'damage':
        return _sections.firstWhere(
          (s) => s.type == _EvidenceSectionType.damageReport,
        );
      default:
        return null;
    }
  }

  String _kindForSection(_EvidenceSectionType type) {
    switch (type) {
      case _EvidenceSectionType.deliveryArrival:
        return 'arrival';
      case _EvidenceSectionType.sealVerification:
        return 'seal_verification';
      case _EvidenceSectionType.damageReport:
        return 'damage_report';
    }
  }

  Future<void> _pickPhoto(
    _EvidenceSectionState section,
    ImageSource source,
  ) async {
    final file = await _picker.pickImage(source: source, imageQuality: 80);
    if (file == null) return;

    double? lat;
    double? lng;
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }
      final position = await Geolocator.getCurrentPosition();
      lat = position.latitude;
      lng = position.longitude;
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      section.photos.add(
        _EvidencePhoto(
          type: section.type,
          localPath: file.path,
          note: section.noteController.text.trim(),
          lat: lat,
          lng: lng,
          timestamp: DateTime.now(),
          status: _EvidenceUploadStatus.queued,
        ),
      );
    });
  }

  bool get _hasRequiredEvidence {
    final arrival = _sections
        .firstWhere((s) => s.type == _EvidenceSectionType.deliveryArrival)
        .photos
        .isNotEmpty;
    final seal = _sections
        .firstWhere((s) => s.type == _EvidenceSectionType.sealVerification)
        .photos
        .isNotEmpty;
    return arrival && seal;
  }

  Future<void> _uploadPhoto(_EvidencePhoto photo) async {
    if (photo.localPath == null || photo.localPath!.isEmpty) return;
    setState(() => photo.status = _EvidenceUploadStatus.uploading);
    try {
      final file = XFile(photo.localPath!);
      await ref.read(tripsRepositoryProvider).uploadEvidence(
            tripId: widget.tripId,
            kind: _kindForSection(photo.type),
            photo: file,
            note: photo.note.isEmpty ? null : photo.note,
            lat: photo.lat,
            lng: photo.lng,
            recordedAt: photo.timestamp,
          );

      final queued = _isQueuedPath(file.path);
      if (!mounted) return;
      setState(() {
        photo.status = queued
            ? _EvidenceUploadStatus.queued
            : _EvidenceUploadStatus.synced;
      });
    } catch (e, st) {
      Logger.e('Evidence upload failed', e, st);
      if (!mounted) return;
      setState(() => photo.status = _EvidenceUploadStatus.failed);
    }
  }

  bool _isQueuedPath(String path) {
    final box = Hive.box<Map>(HiveBoxes.evidenceQueue);
    return box.values.any(
      (q) =>
          q['trip_id'] == widget.tripId &&
          q['type'] == 'evidence' &&
          q['photo_path']?.toString() == path,
    );
  }

  Future<void> _submitAll() async {
    if (!_hasRequiredEvidence) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Delivery Arrival and Seal Verification photos are required.',
          ),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      for (final section in _sections) {
        for (final photo in section.photos) {
          if (photo.status == _EvidenceUploadStatus.synced ||
              photo.status == _EvidenceUploadStatus.uploading) {
            continue;
          }
          await _uploadPhoto(photo);
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Evidence saved. Offline items will sync automatically.'),
        ),
      );
      Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  int get _queuedCount => _sections
      .expand((s) => s.photos)
      .where((p) => p.status == _EvidenceUploadStatus.queued)
      .length;

  int get _failedCount => _sections
      .expand((s) => s.photos)
      .where((p) => p.status == _EvidenceUploadStatus.failed)
      .length;

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Evidence Capture')),
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFF6FAFF), Color(0xFFFFFFFF)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          StickyBottomBar(
            bottomBar: BottomActionBar(
              primary: AppPrimaryButton(
                label: _saving ? 'Saving...' : 'Save Evidence',
                leadingIcon: Icons.cloud_upload_outlined,
                state: _saving
                    ? LoadingButtonState.loading
                    : LoadingButtonState.idle,
                onPressed: _saving ? null : _submitAll,
              ),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_queuedCount > 0 || _failedCount > 0)
                    AlertBanner(
                      type: _failedCount > 0
                          ? AlertType.warning
                          : AlertType.info,
                      message: _failedCount > 0
                          ? '$_failedCount photo(s) failed. Tap retry on each item.'
                          : '$_queuedCount photo(s) queued. Upload continues when signal improves.',
                    ),
                  if (_queuedCount > 0 || _failedCount > 0)
                    const SizedBox(height: AppSpacing.md),
                  for (final section in _sections) ...[
                    _EvidenceSectionCard(
                      section: section,
                      onCaptureCamera: () => _pickPhoto(
                        section,
                        ImageSource.camera,
                      ),
                      onCaptureGallery: () => _pickPhoto(
                        section,
                        ImageSource.gallery,
                      ),
                      onRetryPhoto: _uploadPhoto,
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}

enum _EvidenceSectionType { deliveryArrival, sealVerification, damageReport }

class _EvidenceSectionState {
  _EvidenceSectionState({required this.type, required this.noteController});

  final _EvidenceSectionType type;
  final TextEditingController noteController;
  final List<_EvidencePhoto> photos = [];

  String get title {
    switch (type) {
      case _EvidenceSectionType.deliveryArrival:
        return 'Delivery Arrival ★';
      case _EvidenceSectionType.sealVerification:
        return 'Seal Verification ★';
      case _EvidenceSectionType.damageReport:
        return 'Damage Report';
    }
  }
}

enum _EvidenceUploadStatus { queued, uploading, synced, failed }

class _EvidencePhoto {
  _EvidencePhoto({
    required this.type,
    required this.note,
    required this.timestamp,
    required this.status,
    this.localPath,
    this.remoteUrl,
    this.lat,
    this.lng,
  });

  final _EvidenceSectionType type;
  final String note;
  final DateTime timestamp;
  final String? localPath;
  final String? remoteUrl;
  final double? lat;
  final double? lng;
  _EvidenceUploadStatus status;
}

class _EvidenceSectionCard extends StatelessWidget {
  const _EvidenceSectionCard({
    required this.section,
    required this.onCaptureCamera,
    required this.onCaptureGallery,
    required this.onRetryPhoto,
  });

  final _EvidenceSectionState section;
  final VoidCallback onCaptureCamera;
  final VoidCallback onCaptureGallery;
  final ValueChanged<_EvidencePhoto> onRetryPhoto;

  @override
  Widget build(BuildContext context) {
    final items = section.photos;
    final gridCount = items.length + 1; // +1 for add tile
    return SectionCard(
      title: section.title,
      children: [
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: AppSpacing.sm,
            mainAxisSpacing: AppSpacing.sm,
            childAspectRatio: 1,
          ),
          itemCount: gridCount,
          itemBuilder: (context, index) {
            if (index == items.length) {
              return Container(
                decoration: BoxDecoration(
                  color: AppColors.neutral100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.neutral300),
                ),
                child: const Center(
                  child: Icon(Icons.add, size: 28, color: AppColors.textMuted),
                ),
              );
            }
            final photo = items[index];
            return _EvidencePhotoTile(photo: photo, onRetry: onRetryPhoto);
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: AppSecondaryButton(
                label: 'Camera',
                leadingIcon: Icons.photo_camera,
                onPressed: onCaptureCamera,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: AppSecondaryButton(
                label: 'Gallery',
                leadingIcon: Icons.photo_library_outlined,
                onPressed: onCaptureGallery,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: 'Note for next photo (optional)',
          controller: section.noteController,
          maxLines: 2,
        ),
      ],
    );
  }
}

class _EvidencePhotoTile extends StatelessWidget {
  const _EvidencePhotoTile({required this.photo, required this.onRetry});

  final _EvidencePhoto photo;
  final ValueChanged<_EvidencePhoto> onRetry;

  @override
  Widget build(BuildContext context) {
    Widget image;
    if (photo.localPath != null && photo.localPath!.isNotEmpty) {
      image = Image.file(File(photo.localPath!), fit: BoxFit.cover);
    } else if (photo.remoteUrl != null && photo.remoteUrl!.isNotEmpty) {
      image = Image.network(photo.remoteUrl!, fit: BoxFit.cover);
    } else {
      image = const Center(child: Icon(Icons.image_not_supported_outlined));
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.neutral300),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(child: image),
          Positioned(
            top: 4,
            right: 4,
            child: _statusBadge(photo.status),
          ),
          Positioned(
            left: 4,
            right: 4,
            bottom: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              color: Colors.black.withValues(alpha: 0.45),
              child: Text(
                _metaText(photo),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 10),
              ),
            ),
          ),
          if (photo.status == _EvidenceUploadStatus.uploading)
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: LinearProgressIndicator(minHeight: 2),
            ),
          if (photo.status == _EvidenceUploadStatus.failed)
            Positioned(
              top: 4,
              left: 4,
              child: InkWell(
                onTap: () => onRetry(photo),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'Retry',
                    style: TextStyle(color: Colors.white, fontSize: 10),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _statusBadge(_EvidenceUploadStatus status) {
    final (label, color) = switch (status) {
      _EvidenceUploadStatus.queued => ('Queued', AppColors.accentOrangeDark),
      _EvidenceUploadStatus.uploading => ('Uploading', AppColors.primaryBlue),
      _EvidenceUploadStatus.synced => ('✓', AppColors.successGreen),
      _EvidenceUploadStatus.failed => ('✕', AppColors.errorRed),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  String _metaText(_EvidencePhoto photo) {
    final hh = photo.timestamp.hour.toString().padLeft(2, '0');
    final mm = photo.timestamp.minute.toString().padLeft(2, '0');
    final gps = (photo.lat != null && photo.lng != null)
        ? '${photo.lat!.toStringAsFixed(4)}, ${photo.lng!.toStringAsFixed(4)}'
        : 'No GPS';
    final note = photo.note.isEmpty ? '' : ' • ${photo.note}';
    return '$hh:$mm • $gps$note';
  }
}
