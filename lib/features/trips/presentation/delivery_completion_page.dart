import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/utils/app_theme.dart';
import '../../../core/utils/logger.dart';
import '../../../ui_kit/theme/app_spacing.dart';
import '../../../ui_kit/widgets/buttons.dart';
import '../../../ui_kit/widgets/cards.dart';
import '../../../ui_kit/widgets/forms.dart';
import '../../../ui_kit/widgets/navigation.dart';
import '../data/trips_repository.dart';
import '../domain/trip_stop.dart';

class DeliveryCompletionPage extends ConsumerStatefulWidget {
  const DeliveryCompletionPage({super.key, required this.tripId, this.stop});

  final int tripId;
  final TripStop? stop;

  @override
  ConsumerState<DeliveryCompletionPage> createState() =>
      _DeliveryCompletionPageState();
}

class _DeliveryCompletionPageState
    extends ConsumerState<DeliveryCompletionPage> {
  static const Set<String> _allowedPodTypes = {
    'photo',
    'e_signature',
    'manual',
  };
  final _notesController = TextEditingController();
  bool _waybillReturned = false;
  String _podType = 'photo';
  DateTime _arrivalTime = DateTime.now();
  bool _captureWaybillPhoto = false;
  XFile? _waybillPhoto;
  String? _existingWaybillPhotoUrl;
  bool _loadingInitial = false;
  String _loadStage = 'init';
  String? _loadError;
  String? _loadSummary;
  bool _submitting = false;

  Future<void> _advanceDeliveryStatus(TripsRepository repo) async {
    if (widget.stop != null) return;

    Future<void> move(String status) async {
      try {
        await repo.updateStatus(widget.tripId, status);
      } on DioException catch (e) {
        final code = e.response?.statusCode;
        if (code == 409 || code == 422) {
          return;
        }
        rethrow;
      }
    }

    await move('arrived');
    await move('offloaded');
  }

  @override
  void initState() {
    super.initState();
    Logger.d('DeliveryCompletionPage opened for trip ${widget.tripId}');
    if (widget.stop != null) {
      _notesController.text = widget.stop?.notesIncidents ?? '';
      _waybillReturned = widget.stop?.waybillReturned ?? false;
      final stopPodType = widget.stop?.podType;
      _podType = _allowedPodTypes.contains(stopPodType)
          ? stopPodType!
          : 'photo';
      _arrivalTime = widget.stop?.arrivalTimeAtSite ?? DateTime.now();
    } else {
      _loadExistingTripFields();
    }
  }

  Future<void> _loadExistingTripFields() async {
    setState(() {
      _loadingInitial = true;
      _loadStage = 'fetch_trip';
      _loadError = null;
    });
    try {
      final trip = await ref
          .read(tripsRepositoryProvider)
          .fetchTrip(widget.tripId);
      if (!mounted) return;
      bool parseBool(dynamic value, {bool fallback = false}) {
        if (value is bool) return value;
        if (value is num) return value != 0;
        if (value is String) {
          final v = value.toLowerCase().trim();
          if (v == 'true' || v == '1' || v == 'yes') return true;
          if (v == 'false' || v == '0' || v == 'no') return false;
        }
        return fallback;
      }

      setState(() {
        _notesController.text = trip.notesIncidents ?? '';
        _waybillReturned = parseBool(trip.waybillReturned, fallback: false);
        final incomingPod = trip.podType;
        _podType = _allowedPodTypes.contains(incomingPod)
            ? incomingPod!
            : 'photo';
        _arrivalTime = trip.arrivalTimeAtSite ?? DateTime.now();
        _existingWaybillPhotoUrl = trip.clientRepSignatureUrl;
        _captureWaybillPhoto = (_existingWaybillPhotoUrl?.isNotEmpty ?? false);
        _loadSummary =
            'trip=${trip.id} status=${trip.status} pod=$_podType waybill=$_waybillReturned';
      });
    } catch (e, st) {
      Logger.e('Delivery completion preload failed', e, st);
      if (mounted) {
        setState(() {
          _loadError = 'delivery_load_failed: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loadingInitial = false;
          _loadStage = 'ready';
        });
      }
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      final fields = {
        'arrival_time_at_site': _arrivalTime.toIso8601String(),
        'pod_type': _podType,
        'waybill_returned': _waybillReturned,
        'notes_incidents': _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      };

      if (widget.stop != null) {
        await ref
            .read(tripsRepositoryProvider)
            .updateTripStop(widget.tripId, widget.stop!.id, fields);
      } else {
        await ref
            .read(tripsRepositoryProvider)
            .updateTrip(widget.tripId, fields);
      }

      if (_waybillPhoto != null) {
        await ref
            .read(tripsRepositoryProvider)
            .uploadTripAttachments(
              tripId: widget.tripId,
              clientRepSignature: _waybillPhoto,
            );
      }

      await _advanceDeliveryStatus(ref.read(tripsRepositoryProvider));

      if (mounted) {
        if (widget.stop != null) {
          Navigator.pop(context, true);
        } else {
          Navigator.pop(context, {
            'saved': true,
            'clientRepSignaturePath': _waybillPhoto?.path,
          });
        }
      }
    } catch (e, st) {
      Logger.e('Delivery completion update failed', e, st);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Update failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingInitial) {
      return Scaffold(
        appBar: AppBar(title: const Text('Delivery Completion')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 12),
                Text('Loading: $_loadStage'),
                if (_loadError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _loadError!,
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    final title = widget.stop == null
        ? 'Delivery Completion'
        : 'Stop #${widget.stop!.id} Completion';

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: StickyBottomBar(
        bottomBar: BottomActionBar(
          primary: AppPrimaryButton(
            label: 'Save Delivery Completion',
            leadingIcon: Icons.check_circle_outline,
            state: _submitting
                ? LoadingButtonState.loading
                : LoadingButtonState.idle,
            onPressed: _submitting ? null : _submit,
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
          if (_loadError != null || (kDebugMode && _loadSummary != null))
            Card(
              color: _loadError != null
                  ? Colors.red.shade50
                  : Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Text(
                  _loadError ?? _loadSummary!,
                  style: TextStyle(
                    fontSize: 12,
                    color: _loadError != null
                        ? Colors.red.shade900
                        : Colors.blue.shade900,
                  ),
                ),
              ),
            ),
          if (_loadError != null || (kDebugMode && _loadSummary != null))
            const SizedBox(height: AppSpacing.md),
          SectionCard(
            title: 'Arrival Time',
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _arrivalTime.toLocal().toString(),
                      style: const TextStyle(color: AppTheme.textMuted),
                    ),
                  ),
                  AppSecondaryButton(
                    label: 'Set Now',
                    fullWidth: false,
                    onPressed: () => setState(() => _arrivalTime = DateTime.now()),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          SectionCard(
            title: 'POD Type',
            children: [
              DropdownButtonFormField<String>(
                initialValue: _podType,
                items: const [
                  DropdownMenuItem(value: 'photo', child: Text('Photo')),
                  DropdownMenuItem(
                    value: 'e_signature',
                    child: Text('E-Signature'),
                  ),
                  DropdownMenuItem(value: 'manual', child: Text('Manual')),
                ],
                onChanged: (value) => setState(() => _podType = value ?? 'photo'),
              ),
              const SizedBox(height: AppSpacing.sm),
              ToggleRow(
                label: 'Waybill Returned',
                value: _waybillReturned,
                onChanged: (value) => setState(() => _waybillReturned = value),
              ),
              ToggleRow(
                label: 'Capture Signed Waybill Photo',
                value: _captureWaybillPhoto,
                onChanged: (value) =>
                    setState(() => _captureWaybillPhoto = value),
                showDivider: false,
              ),
              if (_captureWaybillPhoto) ...[
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: AppTheme.background,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: _waybillPhoto == null
                          ? (_existingWaybillPhotoUrl != null &&
                                    _existingWaybillPhotoUrl!.isNotEmpty
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.network(
                                      _existingWaybillPhotoUrl!,
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                : const Icon(
                                    Icons.camera_alt,
                                    color: AppTheme.textMuted,
                                  ))
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.file(
                                File(_waybillPhoto!.path),
                                fit: BoxFit.cover,
                              ),
                            ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    AppSecondaryButton(
                      label: 'Capture',
                      fullWidth: false,
                      leadingIcon: Icons.photo_camera,
                      onPressed: () async {
                        final picker = ImagePicker();
                        final file = await picker.pickImage(
                          source: ImageSource.camera,
                          imageQuality: 80,
                        );
                        if (file != null) {
                          setState(() => _waybillPhoto = file);
                        }
                      },
                    ),
                  ],
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          SectionCard(
            title: 'Notes / Incidents',
            children: [
              AppTextField(
                label: 'Notes (optional)',
                controller: _notesController,
                maxLines: 3,
              ),
            ],
          ),
        ],
      ),
      ),
    );
  }
}
