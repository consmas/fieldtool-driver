import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
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
import '../../fuel/data/fuel_repository.dart';
import '../data/trips_repository.dart';

class FuelPostTripPage extends ConsumerStatefulWidget {
  const FuelPostTripPage({super.key, required this.tripId});

  final int tripId;

  @override
  ConsumerState<FuelPostTripPage> createState() => _FuelPostTripPageState();
}

class _FuelPostTripPageState extends ConsumerState<FuelPostTripPage> {
  static const Set<String> _allowedPaymentModes = {'cash', 'card', 'credit'};
  static const Set<String> _allowedVehicleConditions = {
    'good',
    'requires_service',
    'damaged',
  };

  final _stationController = TextEditingController();
  final _litresController = TextEditingController();
  final _costController = TextEditingController();
  final _fuelOdometerController = TextEditingController();
  final _receiptController = TextEditingController();
  final _inspectorController = TextEditingController();
  final _odometerController = TextEditingController();
  final _odometerNoteController = TextEditingController();

  String _paymentMode = 'cash';
  String _vehicleCondition = 'good';
  DateTime _returnTime = DateTime.now();

  XFile? _odometerPhoto;
  XFile? _proofOfFuellingPhoto;
  String? _existingProofOfFuellingUrl;
  String? _existingEndOdometerPhotoUrl;
  bool _existingEndOdometerPhoto = false;

  bool _loading = true;
  String _loadStage = 'init';
  String? _loadError;
  String? _loadSummary;
  bool _savingFuel = false;
  bool _savingPostTrip = false;
  bool _fullTankFill = false;
  List<FuelLogSubmission> _recentFuelLogs = const [];

  @override
  void initState() {
    super.initState();
    Logger.d('FuelPostTripPage opened for trip ${widget.tripId}');
    _loadTrip();
  }

  @override
  void dispose() {
    _stationController.dispose();
    _litresController.dispose();
    _costController.dispose();
    _fuelOdometerController.dispose();
    _receiptController.dispose();
    _inspectorController.dispose();
    _odometerController.dispose();
    _odometerNoteController.dispose();
    super.dispose();
  }

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
      _stationController.text = trip.fuelStationUsed ?? '';
      _litresController.text = trip.fuelLitresFilled ?? '';
      _costController.text = '';
      _receiptController.text = trip.fuelReceiptNo ?? '';

      final incomingPaymentMode = trip.fuelPaymentMode;
      _paymentMode = _allowedPaymentModes.contains(incomingPaymentMode)
          ? incomingPaymentMode!
          : 'cash';

      final incomingVehicleCondition = trip.vehicleConditionPostTrip;
      _vehicleCondition =
          _allowedVehicleConditions.contains(incomingVehicleCondition)
          ? incomingVehicleCondition!
          : 'good';

      _returnTime = trip.returnTime ?? DateTime.now();
      _inspectorController.text = trip.postTripInspectorName ?? '';
      _odometerController.text = trip.odometerEndKm == null
          ? ''
          : trip.odometerEndKm!.toStringAsFixed(1);
      _fuelOdometerController.text = trip.odometerEndKm == null
          ? (trip.odometerStartKm?.toStringAsFixed(1) ?? '')
          : trip.odometerEndKm!.toStringAsFixed(1);
      _existingProofOfFuellingUrl = trip.proofOfFuellingUrl;
      _existingEndOdometerPhotoUrl = trip.endOdometerPhotoUrl;
      _existingEndOdometerPhoto =
          trip.endOdometerPhotoUrl != null &&
          trip.endOdometerPhotoUrl!.isNotEmpty;
      _loadSummary =
          'trip=${trip.id} status=${trip.status} payment=$_paymentMode vehicle=$_vehicleCondition end_odo=${trip.odometerEndKm ?? '-'}';
      await _loadRecentFuelLogs();
    } catch (e, st) {
      Logger.e('Failed to load trip for fuel/post-trip', e, st);
      if (mounted) {
        setState(() {
          _loadError = 'fuel_post_trip_load_failed: $e';
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

  Future<void> _loadRecentFuelLogs() async {
    final logs = await ref
        .read(fuelRepositoryProvider)
        .recentSubmissions(tripId: widget.tripId, limit: 8);
    if (!mounted) return;
    setState(() => _recentFuelLogs = logs);
  }

  Future<void> _pickImage(ValueSetter<XFile?> setter) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
    );
    if (file != null && mounted) {
      setState(() => setter(file));
    }
  }

  Future<void> _submitFuel() async {
    if (_savingFuel || _savingPostTrip) return;
    final litres = double.tryParse(_litresController.text.trim());
    final cost = double.tryParse(_costController.text.trim());
    final odo = double.tryParse(_fuelOdometerController.text.trim());

    if (litres == null || litres <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter valid litres (> 0).')),
      );
      return;
    }
    if (cost == null || cost <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter valid fuel cost (> 0).')),
      );
      return;
    }
    if (odo == null || odo <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter valid odometer value (> 0).')),
      );
      return;
    }

    setState(() => _savingFuel = true);
    try {
      await ref
          .read(fuelRepositoryProvider)
          .submitTripFuelLog(
            tripId: widget.tripId,
            litres: litres,
            cost: cost,
            odometerKm: odo,
            fullTank: _fullTankFill,
            station: _stationController.text.trim(),
            note: _receiptController.text.trim().isEmpty
                ? null
                : 'receipt:${_receiptController.text.trim()}',
          );

      final fields = {
        'fuel_station_used': _stationController.text.trim().isEmpty
            ? null
            : _stationController.text.trim(),
        'fuel_payment_mode': _paymentMode,
        'fuel_litres_filled': _litresController.text.trim().isEmpty
            ? null
            : _litresController.text.trim(),
        'fuel_receipt_no': _receiptController.text.trim().isEmpty
            ? null
            : _receiptController.text.trim(),
      };

      await ref.read(tripsRepositoryProvider).updateTrip(widget.tripId, fields);
      if (_proofOfFuellingPhoto != null) {
        await ref
            .read(tripsRepositoryProvider)
            .uploadTripAttachments(
              tripId: widget.tripId,
              proofOfFuelling: _proofOfFuellingPhoto,
            );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Fuel details saved.')));
      await _loadRecentFuelLogs();
    } catch (e, st) {
      Logger.e('Fuel update failed', e, st);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Fuel save failed: $e')));
    } finally {
      if (mounted) setState(() => _savingFuel = false);
    }
  }

  Future<void> _submitPostTrip() async {
    if (_savingPostTrip || _savingFuel) return;

    final endKm = double.tryParse(_odometerController.text.trim());
    if (endKm == null || endKm <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid end odometer value.')),
      );
      return;
    }
    if (_odometerPhoto == null && !_existingEndOdometerPhoto) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End odometer photo is required.')),
      );
      return;
    }

    setState(() => _savingPostTrip = true);
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

      if (_odometerPhoto != null) {
        await ref
            .read(tripsRepositoryProvider)
            .uploadOdometerEnd(
              tripId: widget.tripId,
              valueKm: endKm,
              photo: _odometerPhoto!,
              lat: lat ?? 0,
              lng: lng ?? 0,
              note: _odometerNoteController.text.trim().isEmpty
                  ? null
                  : _odometerNoteController.text.trim(),
            );
      }

      final fields = {
        'return_time': _returnTime.toIso8601String(),
        'vehicle_condition_post_trip': _vehicleCondition,
        'post_trip_inspector_name': _inspectorController.text.trim().isEmpty
            ? null
            : _inspectorController.text.trim(),
      };
      await ref.read(tripsRepositoryProvider).updateTrip(widget.tripId, fields);

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Post-trip details saved.')));
      Navigator.pop(context, _proofOfFuellingPhoto?.path);
    } catch (e, st) {
      Logger.e('Post-trip update failed', e, st);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Post-trip save failed: $e')));
    } finally {
      if (mounted) setState(() => _savingPostTrip = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: const ConsMasAppBar(title: 'Fuel & Post-Trip'),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: AppSpacing.sm),
                Text('Loading: $_loadStage'),
                if (_loadError != null) ...[
                  const SizedBox(height: AppSpacing.xs),
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
      appBar: const ConsMasAppBar(title: 'Fuel & Post-Trip'),
      body: StickyBottomBar(
        bottomBar: BottomActionBar(
          secondary: AppSecondaryButton(
            label: 'Save Fuel',
            onPressed: (_savingFuel || _savingPostTrip) ? null : _submitFuel,
          ),
          primary: AppPrimaryButton(
            label: 'Save Post-Trip',
            leadingIcon: Icons.task_alt,
            state: _savingPostTrip
                ? LoadingButtonState.loading
                : LoadingButtonState.idle,
            onPressed: (_savingFuel || _savingPostTrip)
                ? null
                : _submitPostTrip,
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            if (_loadError != null || (kDebugMode && _loadSummary != null))
              Container(
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: _loadError != null
                      ? AppColors.errorRedLight
                      : AppColors.primaryBlueLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(_loadError ?? _loadSummary!),
              ),
            SectionCard(
              title: 'Fuel Refilling',
              children: [
                AppTextField(
                  label: 'Fuel Station Used',
                  controller: _stationController,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Payment Mode',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(height: AppSpacing.xs),
                DropdownButtonFormField<String>(
                  initialValue: _paymentMode,
                  items: const [
                    DropdownMenuItem(value: 'cash', child: Text('Cash')),
                    DropdownMenuItem(value: 'card', child: Text('Card')),
                    DropdownMenuItem(value: 'credit', child: Text('Credit')),
                  ],
                  onChanged: (value) =>
                      setState(() => _paymentMode = value ?? 'cash'),
                ),
                const SizedBox(height: AppSpacing.sm),
                AppTextField(
                  label: 'Fuel Litres Filled',
                  controller: _litresController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                AppTextField(
                  label: 'Fuel Cost',
                  controller: _costController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                AppTextField(
                  label: 'Odometer at Fueling (km)',
                  controller: _fuelOdometerController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                AppTextField(
                  label: 'Fuel Receipt No.',
                  controller: _receiptController,
                ),
                const SizedBox(height: AppSpacing.sm),
                SwitchListTile.adaptive(
                  value: _fullTankFill,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Full Tank Fill'),
                  subtitle: const Text(
                    'Mark this fueling as full-tank for efficiency tracking.',
                  ),
                  onChanged: (v) => setState(() => _fullTankFill = v),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            SectionCard(
              title: 'Last Fuel Submissions',
              children: [
                if (_recentFuelLogs.isEmpty)
                  const Text('No recent fuel logs.')
                else
                  ..._recentFuelLogs.map((entry) {
                    final syncStatus = switch (entry.status) {
                      FuelLogSyncStatus.synced => SyncStatus.synced,
                      FuelLogSyncStatus.failed => SyncStatus.failed,
                      FuelLogSyncStatus.queued => SyncStatus.queued,
                    };
                    return InfoRow(
                      label:
                          '${entry.recordedAt.toLocal().toString().substring(0, 16)} · ${entry.litres.toStringAsFixed(1)}L',
                      valueWidget: SyncStatusBadge(status: syncStatus),
                      showDivider: entry != _recentFuelLogs.last,
                    );
                  }),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            SectionCard(
              title: 'Proof of Fuelling',
              children: [
                _PhotoRow(
                  label: 'Fuel Proof Photo',
                  file: _proofOfFuellingPhoto,
                  existingUrl: _existingProofOfFuellingUrl,
                  onPick: () =>
                      _pickImage((file) => _proofOfFuellingPhoto = file),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            SectionCard(
              title: 'End Odometer',
              children: [
                AppTextField(
                  label: 'Odometer (km)',
                  controller: _odometerController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                AppTextField(
                  label: 'Note (optional)',
                  controller: _odometerNoteController,
                ),
                const SizedBox(height: AppSpacing.sm),
                _PhotoRow(
                  label: _existingEndOdometerPhoto && _odometerPhoto == null
                      ? 'Odometer Photo (already uploaded)'
                      : 'Odometer Photo (required)',
                  file: _odometerPhoto,
                  existingUrl: _existingEndOdometerPhotoUrl,
                  onPick: () => _pickImage((file) => _odometerPhoto = file),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            SectionCard(
              title: 'Post-Trip',
              children: [
                InfoRow(
                  label: 'Return Time',
                  value: _returnTime.toLocal().toString(),
                ),
                const SizedBox(height: AppSpacing.sm),
                AppSecondaryButton(
                  label: 'Set Return Time to Now',
                  fullWidth: false,
                  onPressed: () => setState(() => _returnTime = DateTime.now()),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Vehicle Condition',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(height: AppSpacing.xs),
                DropdownButtonFormField<String>(
                  initialValue: _vehicleCondition,
                  items: const [
                    DropdownMenuItem(value: 'good', child: Text('Good')),
                    DropdownMenuItem(
                      value: 'requires_service',
                      child: Text('Requires Service'),
                    ),
                    DropdownMenuItem(value: 'damaged', child: Text('Damaged')),
                  ],
                  onChanged: (value) =>
                      setState(() => _vehicleCondition = value ?? 'good'),
                ),
                const SizedBox(height: AppSpacing.sm),
                AppTextField(
                  label: 'Inspector Name',
                  controller: _inspectorController,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }
}

class _PhotoRow extends StatelessWidget {
  const _PhotoRow({
    required this.label,
    required this.file,
    required this.existingUrl,
    required this.onPick,
  });

  final String label;
  final XFile? file;
  final String? existingUrl;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final hasImage = file != null || (existingUrl?.isNotEmpty ?? false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.neutral100,
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
                  : const Icon(Icons.camera_alt, color: AppColors.textMuted),
            ),
            const SizedBox(width: AppSpacing.sm),
            AppSecondaryButton(
              label: 'Capture',
              fullWidth: false,
              leadingIcon: Icons.photo_camera,
              onPressed: onPick,
            ),
          ],
        ),
      ],
    );
  }
}
