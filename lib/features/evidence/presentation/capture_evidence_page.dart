import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/utils/logger.dart';
import '../../trips/data/trips_repository.dart';

class CaptureEvidencePage extends ConsumerStatefulWidget {
  const CaptureEvidencePage({
    super.key,
    required this.tripId,
  });

  final int tripId;

  @override
  ConsumerState<CaptureEvidencePage> createState() => _CaptureEvidencePageState();
}

class _CaptureEvidencePageState extends ConsumerState<CaptureEvidencePage> {
  final _noteController = TextEditingController();
  final _picker = ImagePicker();
  XFile? _photo;
  String _kind = 'arrival';
  bool _saving = false;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _capturePhoto() async {
    final file = await _picker.pickImage(source: ImageSource.camera, imageQuality: 80);
    if (file != null) {
      setState(() => _photo = file);
    }
  }

  Future<void> _submit() async {
    if (_photo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Evidence photo is required.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
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

      await ref.read(tripsRepositoryProvider).uploadEvidence(
            tripId: widget.tripId,
            kind: _kind,
            photo: _photo!,
            note: _noteController.text.trim(),
            lat: lat,
            lng: lng,
            recordedAt: DateTime.now(),
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e, st) {
      Logger.e('Evidence upload failed', e, st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Capture Evidence')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            initialValue: _kind,
            decoration: const InputDecoration(labelText: 'Evidence Type'),
            items: const [
              DropdownMenuItem(value: 'before_loading', child: Text('Before Loading')),
              DropdownMenuItem(value: 'after_loading', child: Text('After Loading')),
              DropdownMenuItem(value: 'en_route', child: Text('En Route')),
              DropdownMenuItem(value: 'arrival', child: Text('Arrival')),
              DropdownMenuItem(value: 'offloading', child: Text('Offloading')),
            ],
            onChanged: (value) => setState(() => _kind = value ?? 'arrival'),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _capturePhoto,
            icon: const Icon(Icons.photo_camera),
            label: Text(_photo == null ? 'Capture Photo' : 'Retake Photo'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _noteController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Note (optional)',
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _saving ? null : _submit,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Upload Evidence'),
          ),
        ],
      ),
    );
  }
}
