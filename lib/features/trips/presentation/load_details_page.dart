import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/utils/app_theme.dart';
import '../../../core/utils/logger.dart';
import '../../../ui_kit/models/enums.dart';
import '../../../ui_kit/theme/app_colors.dart';
import '../../../ui_kit/theme/app_spacing.dart';
import '../../../ui_kit/widgets/badges.dart';
import '../../../ui_kit/widgets/buttons.dart';
import '../../../ui_kit/widgets/cards.dart';
import '../../../ui_kit/widgets/forms.dart';
import '../../../ui_kit/widgets/navigation.dart';
import '../data/trips_repository.dart';
import '../domain/trip.dart';

class LoadDetailsPage extends ConsumerStatefulWidget {
  const LoadDetailsPage({super.key, required this.tripId});

  final int tripId;

  @override
  ConsumerState<LoadDetailsPage> createState() => _LoadDetailsPageState();
}

class _LoadDetailsPageState extends ConsumerState<LoadDetailsPage> {
  static const Set<String> _allowedLoadStatus = {'full', 'partial'};

  final _waybillController = TextEditingController();
  final _loadNoteController = TextEditingController();
  final _assistantNameController = TextEditingController();
  final _assistantPhoneController = TextEditingController();
  final _fuelLevelController = TextEditingController();

  bool _loading = true;
  String _loadStage = 'init';
  String? _loadError;
  String? _loadSummary;
  bool _submitting = false;

  Trip? _trip;

  XFile? _driverSignature;
  XFile? _securitySignature;
  XFile? _loadPhoto;
  XFile? _waybillPhoto;

  String? _existingDriverSignatureUrl;
  String? _existingSecuritySignatureUrl;
  String? _existingLoadPhotoUrl;
  String? _existingWaybillPhotoUrl;

  String _loadStatus = 'full';
  bool _loadAreaReady = true;
  bool _loadSecured = false;
  bool _loadWithinWeight = true;
  String _sealStatus = 'intact';

  @override
  void initState() {
    super.initState();
    Logger.d('LoadDetailsPage opened for trip ${widget.tripId}');
    _loadTrip();
  }

  @override
  void dispose() {
    _waybillController.dispose();
    _loadNoteController.dispose();
    _assistantNameController.dispose();
    _assistantPhoneController.dispose();
    _fuelLevelController.dispose();
    super.dispose();
  }

  bool get _hasHazmatOrPerishable {
    final text =
        '${_trip?.materialDescription ?? ''} ${_trip?.specialInstructions ?? ''}'
            .toLowerCase();
    return text.contains('hazmat') ||
        text.contains('hazard') ||
        text.contains('perishable') ||
        text.contains('flammable');
  }

  int get _evidenceCount {
    var count = 0;
    if (_loadPhoto != null || (_existingLoadPhotoUrl?.isNotEmpty ?? false)) {
      count += 1;
    }
    if (_waybillPhoto != null ||
        (_existingWaybillPhotoUrl?.isNotEmpty ?? false)) {
      count += 1;
    }
    return count;
  }

  bool get _canConfirm => _evidenceCount >= 2 && _loadAreaReady;

  Future<void> _loadTrip() async {
    if (mounted) {
      setState(() {
        _loadStage = 'fetch_trip';
        _loadError = null;
      });
    }
    try {
      final trip = await ref
          .read(tripsRepositoryProvider)
          .fetchTrip(widget.tripId);
      if (!mounted) return;
      setState(() {
        _trip = trip;
        _waybillController.text = trip.waybillNumber ?? trip.referenceCode;
        _existingDriverSignatureUrl = trip.driverSignatureUrl;
        _existingSecuritySignatureUrl = trip.securitySignatureUrl;
      });

      final rawPreTrip = await ref
          .read(tripsRepositoryProvider)
          .fetchPreTrip(widget.tripId);
      if (mounted) {
        setState(() => _loadStage = 'fetch_pre_trip');
      }

      final preTrip = rawPreTrip == null
          ? null
          : (rawPreTrip['pre_trip'] is Map<String, dynamic>
                ? rawPreTrip['pre_trip'] as Map<String, dynamic>
                : rawPreTrip);

      if (preTrip != null) {
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

        final note = preTrip['load_note']?.toString() ?? '';
        final sealFromNote = _extractSealStatus(note);

        if (!mounted) return;
        setState(() {
          final incomingLoadStatus = preTrip['load_status']?.toString();
          _loadStatus = _allowedLoadStatus.contains(incomingLoadStatus)
              ? incomingLoadStatus!
              : 'full';
          _loadAreaReady = parseBool(
            preTrip['load_area_ready'],
            fallback: true,
          );
          _loadSecured = parseBool(preTrip['load_secured'], fallback: false);
          _loadWithinWeight = parseBool(
            preTrip['load_within_weight'],
            fallback: true,
          );
          _sealStatus = sealFromNote ?? (_loadSecured ? 'intact' : 'missing');
          _loadNoteController.text = _stripSealStatus(note);
          _assistantNameController.text =
              preTrip['assistant_name']?.toString() ?? '';
          _assistantPhoneController.text =
              preTrip['assistant_phone']?.toString() ?? '';
          _fuelLevelController.text = preTrip['fuel_level']?.toString() ?? '';
          _existingLoadPhotoUrl = preTrip['load_photo_url']?.toString();
          _existingWaybillPhotoUrl = preTrip['waybill_photo_url']?.toString();
          _loadSummary =
              'trip=${trip.id} status=${trip.status} load_status=$_loadStatus seal=$_sealStatus';
        });
      } else if (mounted) {
        setState(() {
          _loadSummary = 'trip=${trip.id} status=${trip.status} no_pre_trip';
        });
      }
    } catch (e, st) {
      Logger.e('Failed to load trip for load details', e, st);
      if (mounted) {
        setState(() {
          _loadError = 'load_details_load_failed: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadStage = 'ready';
        });
      }
    }
  }

  String? _extractSealStatus(String note) {
    final lower = note.toLowerCase();
    if (lower.contains('[seal_status=intact]')) return 'intact';
    if (lower.contains('[seal_status=broken]')) return 'broken';
    if (lower.contains('[seal_status=missing]')) return 'missing';
    return null;
  }

  String _stripSealStatus(String note) {
    return note
        .replaceAll(
          RegExp(
            r'\[seal_status=(intact|broken|missing)\]\s*',
            caseSensitive: false,
          ),
          '',
        )
        .trim();
  }

  Future<void> _pickPhoto(ValueSetter<XFile?> setter) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
    );
    if (file != null) {
      setState(() => setter(file));
    }
  }

  Future<void> _pickPhotoWithChoice(ValueSetter<XFile?> setter) async {
    await _pickPhoto(setter);
  }

  Future<void> _submit() async {
    if (!_canConfirm) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add required loading evidence photos.'),
        ),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final waybill = _waybillController.text.trim();
      final note = _loadNoteController.text.trim();
      final composedNote =
          '[seal_status=$_sealStatus]${note.isEmpty ? '' : ' $note'}';

      final fields = <String, dynamic>{
        'pre_trip[load_area_ready]': _loadAreaReady,
        'pre_trip[load_status]': _loadStatus,
        'pre_trip[load_secured]': _sealStatus == 'intact',
        'pre_trip[load_within_weight]': _loadWithinWeight,
        'pre_trip[load_note]': composedNote,
        'pre_trip[assistant_name]': _assistantNameController.text.trim().isEmpty
            ? null
            : _assistantNameController.text.trim(),
        'pre_trip[assistant_phone]':
            _assistantPhoneController.text.trim().isEmpty
            ? null
            : _assistantPhoneController.text.trim(),
        'pre_trip[fuel_level]': _fuelLevelController.text.trim().isEmpty
            ? null
            : _fuelLevelController.text.trim(),
      };

      if (waybill.isNotEmpty) {
        fields['pre_trip[waybill_number]'] = waybill;
      }

      final repo = ref.read(tripsRepositoryProvider);

      if (_loadPhoto != null) {
        fields['pre_trip[load_photo]'] = await repo.createMultipartFile(
          _loadPhoto!,
        );
      }
      if (_waybillPhoto != null) {
        fields['pre_trip[waybill_photo]'] = await repo.createMultipartFile(
          _waybillPhoto!,
        );
      }

      if (fields.isNotEmpty) {
        await repo.updatePreTripFields(widget.tripId, fields);
      }

      await repo.uploadTripAttachments(
        tripId: widget.tripId,
        driverSignature: _driverSignature,
        securitySignature: _securitySignature,
      );

      if (_loadSecured || _sealStatus == 'intact') {
        try {
          await repo.updateStatus(widget.tripId, 'loaded');
        } catch (e, st) {
          Logger.e('Set status loaded failed', e, st);
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Load details saved and queued for sync.'),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e, st) {
      Logger.e('Load details save failed', e, st);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Load Details')),
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

    return Scaffold(
      appBar: AppBar(title: const Text('Load Details')),
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
                label: 'Confirm Load Accepted ✓',
                leadingIcon: Icons.verified,
                state: _submitting
                    ? LoadingButtonState.loading
                    : (_canConfirm
                          ? LoadingButtonState.idle
                          : LoadingButtonState.error),
                onPressed: (_submitting || !_canConfirm) ? null : _submit,
              ),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                children: [
                  if (_loadError != null ||
                      (kDebugMode && _loadSummary != null))
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
                  if (_loadError != null ||
                      (kDebugMode && _loadSummary != null))
                    const SizedBox(height: AppSpacing.md),

                  if (_hasHazmatOrPerishable)
                    const Padding(
                      padding: EdgeInsets.only(bottom: AppSpacing.md),
                      child: AlertBanner(
                        type: AlertType.warning,
                        message:
                            'Perishable/Hazmat handling flag detected. Follow handling instructions before departure.',
                      ),
                    ),

                  SectionCard(
                    title: 'Load Summary',
                    children: [
                      InfoRow(
                        label: 'Trip Ref',
                        value: _trip?.referenceCode ?? '—',
                      ),
                      InfoRow(label: 'Client', value: _trip?.clientName ?? '—'),
                      InfoRow(
                        label: 'Material',
                        value: _trip?.materialDescription ?? '—',
                      ),
                      InfoRow(
                        label: 'Tonnage',
                        value: _trip?.tonnageLoad ?? '—',
                      ),
                      InfoRow(
                        label: 'Waybill Number',
                        value:
                            _trip?.waybillNumber ?? _trip?.referenceCode ?? '—',
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),

                  SectionCard(
                    title: 'Load Readiness',
                    children: [
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _loadAreaReady,
                        onChanged: (v) =>
                            setState(() => _loadAreaReady = v ?? false),
                        title: const Text('Load Area Ready'),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _loadSecured,
                        onChanged: (v) => setState(() {
                          final checked = v ?? false;
                          _loadSecured = checked;
                          if (checked) _sealStatus = 'intact';
                        }),
                        title: const Text('Load Secured'),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _loadWithinWeight,
                        onChanged: (v) =>
                            setState(() => _loadWithinWeight = v ?? false),
                        title: const Text('Load Within Weight'),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),

                  SectionCard(
                    title: 'Seals',
                    children: [
                      Text(
                        'Seal Status',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Wrap(
                        spacing: AppSpacing.sm,
                        children: [
                          _SealChip(
                            label: 'Intact',
                            selected: _sealStatus == 'intact',
                            onTap: () => setState(() {
                              _sealStatus = 'intact';
                              _loadSecured = true;
                            }),
                          ),
                          _SealChip(
                            label: 'Broken',
                            selected: _sealStatus == 'broken',
                            onTap: () => setState(() {
                              _sealStatus = 'broken';
                              _loadSecured = false;
                            }),
                          ),
                          _SealChip(
                            label: 'Missing',
                            selected: _sealStatus == 'missing',
                            onTap: () => setState(() {
                              _sealStatus = 'missing';
                              _loadSecured = false;
                            }),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),

                  SectionCard(
                    title: 'Instructions',
                    children: [
                      InfoRow(
                        label: 'Special Instructions',
                        value: _trip?.specialInstructions ?? 'None',
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      AppTextField(
                        label: 'Handling Note',
                        controller: _loadNoteController,
                        hint: 'Optional note for loading team',
                        maxLines: 2,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),

                  SectionCard(
                    title: 'Photo Evidence',
                    children: [
                      AppProgressBar(
                        value: (_evidenceCount / 2).clamp(0, 1),
                        label: 'Required photos',
                        valueLabel: '$_evidenceCount of 2',
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        children: [
                          Expanded(
                            child: _EvidenceTile(
                              title: 'Load Photo',
                              file: _loadPhoto,
                              existingUrl: _existingLoadPhotoUrl,
                              onPick: () =>
                                  _pickPhotoWithChoice((f) => _loadPhoto = f),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: _EvidenceTile(
                              title: 'Waybill Photo',
                              file: _waybillPhoto,
                              existingUrl: _existingWaybillPhotoUrl,
                              onPick: () => _pickPhotoWithChoice(
                                (f) => _waybillPhoto = f,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),

                  SectionCard(
                    title: 'Assistant',
                    children: [
                      AppTextField(
                        label: 'Assistant Name',
                        controller: _assistantNameController,
                        hint: 'Optional',
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      AppTextField(
                        label: 'Assistant Phone',
                        controller: _assistantPhoneController,
                        hint: 'Optional',
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      AppTextField(
                        label: 'Fuel Level',
                        controller: _fuelLevelController,
                        hint: 'Optional',
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),

                  SectionCard(
                    title: 'Signatures',
                    children: [
                      _SignatureRow(
                        title: 'Driver Signature',
                        file: _driverSignature,
                        existingUrl: _existingDriverSignatureUrl,
                        onCapture: () =>
                            _pickPhotoWithChoice((f) => _driverSignature = f),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _SignatureRow(
                        title: 'Security Signature',
                        file: _securitySignature,
                        existingUrl: _existingSecuritySignatureUrl,
                        onCapture: () =>
                            _pickPhotoWithChoice((f) => _securitySignature = f),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EvidenceTile extends StatelessWidget {
  const _EvidenceTile({
    required this.title,
    required this.file,
    required this.existingUrl,
    required this.onPick,
  });

  final String title;
  final XFile? file;
  final String? existingUrl;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final hasImage = file != null || (existingUrl?.isNotEmpty ?? false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: AppSpacing.xs),
        GestureDetector(
          onTap: onPick,
          child: Container(
            height: 108,
            decoration: BoxDecoration(
              color: AppTheme.background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.neutral300),
            ),
            child: hasImage
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: file != null
                        ? Image.file(File(file!.path), fit: BoxFit.cover)
                        : Image.network(existingUrl!, fit: BoxFit.cover),
                  )
                : const Center(
                    child: Icon(
                      Icons.add_a_photo_outlined,
                      color: AppTheme.textMuted,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _SealChip extends StatelessWidget {
  const _SealChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryBlue : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AppColors.primaryBlue : AppColors.neutral300,
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: selected ? Colors.white : AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _SignatureRow extends StatelessWidget {
  const _SignatureRow({
    required this.title,
    required this.file,
    required this.existingUrl,
    required this.onCapture,
  });

  final String title;
  final XFile? file;
  final String? existingUrl;
  final VoidCallback onCapture;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.labelMedium),
        ),
        const SizedBox(width: AppSpacing.sm),
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: AppTheme.background,
            borderRadius: BorderRadius.circular(12),
          ),
          child: file != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(File(file!.path), fit: BoxFit.cover),
                )
              : (existingUrl != null && existingUrl!.isNotEmpty)
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(existingUrl!, fit: BoxFit.cover),
                )
              : const Icon(Icons.edit, color: AppTheme.textMuted),
        ),
        const SizedBox(width: AppSpacing.sm),
        AppSecondaryButton(
          label: 'Capture',
          fullWidth: false,
          leadingIcon: Icons.photo_camera,
          onPressed: onCapture,
        ),
      ],
    );
  }
}
