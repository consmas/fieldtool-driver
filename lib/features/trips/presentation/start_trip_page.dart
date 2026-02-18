import 'dart:convert';
import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive/hive.dart';

import '../../../core/utils/logger.dart';
import '../../../ui_kit/theme/app_colors.dart';
import '../../../ui_kit/theme/app_spacing.dart';
import '../../../ui_kit/widgets/cards.dart';
import '../../../ui_kit/widgets/navigation.dart';
import '../../offline/hive_boxes.dart';
import '../../tracking/service/tracking_service.dart';
import '../data/trips_repository.dart';
import '../domain/trip.dart';
import 'live_tracking_page.dart';
import 'widgets/slide_action.dart';

class StartTripPage extends ConsumerStatefulWidget {
  const StartTripPage({super.key, required this.tripId});

  final int tripId;

  @override
  ConsumerState<StartTripPage> createState() => _StartTripPageState();
}

class _StartTripPageState extends ConsumerState<StartTripPage> {
  final _odometerController = TextEditingController();

  bool _loading = true;
  bool _submitting = false;
  String? _error;
  Trip? _trip;
  Map<String, dynamic>? _preTrip;
  Position? _gps;
  bool _isOnline = true;
  StreamSubscription<Position>? _positionSub;
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  DateTime _departureTimestamp = DateTime.now();

  @override
  void initState() {
    super.initState();
    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      if (!mounted) return;
      setState(
        () => _isOnline = results.any((r) => r != ConnectivityResult.none),
      );
    });
    _load();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _connSub?.cancel();
    _odometerController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(tripsRepositoryProvider);
      final trip = await repo.fetchTrip(widget.tripId);
      final preTripRaw = await repo.fetchPreTrip(widget.tripId);
      final preTrip = preTripRaw == null
          ? null
          : (preTripRaw['pre_trip'] is Map<String, dynamic>
                ? preTripRaw['pre_trip'] as Map<String, dynamic>
                : preTripRaw);

      Position? gps;
      try {
        final permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          await Geolocator.requestPermission();
        }
        gps = await Geolocator.getCurrentPosition();
        _positionSub?.cancel();
        _positionSub = Geolocator.getPositionStream().listen((position) {
          if (!mounted) return;
          setState(() => _gps = position);
        });
      } catch (_) {}

      final prefill =
          preTrip?['odometer_value_km']?.toString() ??
          trip.odometerStartKm?.toString() ??
          '';

      if (!mounted) return;
      setState(() {
        _trip = trip;
        _preTrip = preTrip;
        _gps = gps;
        _odometerController.text = prefill;
        _loading = false;
      });
    } catch (e, st) {
      Logger.e('Failed to load start trip page', e, st);
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  bool _toBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final v = value.toLowerCase().trim();
      return v == 'true' || v == '1' || v == 'yes';
    }
    return false;
  }

  bool get _hasOdometer =>
      (double.tryParse(_odometerController.text.trim()) ?? 0) > 0;

  bool get _loadConfirmed {
    if (_trip?.status == 'loaded') return true;
    final pre = _preTrip;
    if (pre == null) return false;
    return _toBool(pre['load_area_ready']) && _toBool(pre['load_secured']);
  }

  bool get _checklistCompletedOrSkipped {
    final pre = _preTrip;
    if (pre == null) return false;
    final checklistValue = pre['core_checklist'] ?? pre['core_checklist_json'];
    final parsed = _parseChecklist(checklistValue);
    if (parsed.isEmpty) return _toBool(pre['accepted']);
    return parsed.values.every(
      (status) => status == 'pass' || status == 'fail' || status == 'na',
    );
  }

  Map<String, String> _parseChecklist(dynamic value) {
    dynamic payload = value;
    if (payload is String && payload.trim().isNotEmpty) {
      try {
        payload = jsonDecode(payload);
      } catch (_) {
        return {};
      }
    }
    if (payload is! Map) return {};

    final out = <String, String>{};
    payload.forEach((k, v) {
      if (v is String) {
        out[k.toString()] = v.toLowerCase();
      } else if (v is Map) {
        out[k.toString()] = (v['status']?.toString().toLowerCase() ?? '');
      }
    });
    return out;
  }

  bool get _canStart =>
      _hasOdometer && _loadConfirmed && _checklistCompletedOrSkipped;

  int get _pendingStatusCount {
    final box = Hive.box<Map>(HiveBoxes.statusQueue);
    return box.values.where((e) => e['trip_id'] == widget.tripId).length;
  }

  int get _pendingMediaCount {
    final box = Hive.box<Map>(HiveBoxes.evidenceQueue);
    return box.values.where((e) => e['trip_id'] == widget.tripId).length;
  }

  int get _pendingPreTripCount {
    final box = Hive.box<Map>(HiveBoxes.preTripQueue);
    return box.values.where((e) => e['trip_id'] == widget.tripId).length;
  }

  List<String> get _missingRequirements {
    final missing = <String>[];
    if (!_hasOdometer) missing.add('Enter departure odometer');
    if (!_loadConfirmed) missing.add('Confirm load details');
    if (!_checklistCompletedOrSkipped) {
      missing.add('Complete/skip pre-trip checklist');
    }
    return missing;
  }

  int get _checklistItemsCount {
    final pre = _preTrip;
    if (pre == null) return 0;
    final checklistValue = pre['core_checklist'] ?? pre['core_checklist_json'];
    return _parseChecklist(checklistValue).length;
  }

  Future<void> _startTrip() async {
    if (!_canStart || _submitting) return;
    setState(() => _submitting = true);
    try {
      final now = DateTime.now();
      setState(() => _departureTimestamp = now);
      await ref.read(tripsRepositoryProvider).updateTrip(widget.tripId, {
        'estimated_departure_time': now.toIso8601String(),
      });
      await ref
          .read(trackingServiceProvider.notifier)
          .startTracking(tripId: widget.tripId);
      await ref
          .read(tripsRepositoryProvider)
          .updateStatus(widget.tripId, 'en_route');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Trip started. GPS tracking is active (queued if offline).',
          ),
        ),
      );
      Navigator.pop(context, true);
    } catch (e, st) {
      Logger.e('Start trip failed', e, st);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Start failed: $e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Start Trip')),
        body: Center(child: Text('Failed to load: $_error')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Start Trip')),
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
            bottomBar: Container(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: AppColors.neutral200)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SlideAction(
                    label: 'Slide to Start Trip →',
                    enabled: _canStart && !_submitting,
                    completionThreshold: 0.80,
                    enableHaptic: true,
                    onSubmit: _startTrip,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'GPS will begin tracking once trip is started',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                  ),
                  if (!_canStart)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: Text(
                        'Complete odometer, load confirmation, and checklist before starting.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.errorRed,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SectionCard(
                    title: 'Trip Snapshot',
                    children: [
                      InfoRow(
                        label: 'Reference',
                        value: _trip?.referenceCode ?? '—',
                      ),
                      InfoRow(
                        label: 'Waybill',
                        value: _trip?.waybillNumber ?? '—',
                      ),
                      InfoRow(
                        label: 'Destination',
                        value: _trip?.destination ?? '—',
                      ),
                      InfoRow(
                        label: 'Current Status',
                        value: _trip?.status ?? '—',
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SectionCard(
                    title: 'Departure Odometer',
                    children: [
                      Text(
                        _odometerController.text.isEmpty
                            ? '—'
                            : '${double.tryParse(_odometerController.text.trim())?.toStringAsFixed(1) ?? _odometerController.text} km',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.primaryBlue,
                            ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      TextField(
                        controller: _odometerController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Odometer (km)',
                          hintText: 'Enter departure odometer',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        _gps == null
                            ? 'GPS suggestion unavailable'
                            : 'GPS suggestion: ${_gps!.latitude.toStringAsFixed(5)}, ${_gps!.longitude.toStringAsFixed(5)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SectionCard(
                    title: 'Pre-Departure Summary',
                    children: [
                      InfoRow(
                        label: 'Load Confirmed',
                        value: _loadConfirmed ? 'Yes' : 'No',
                      ),
                      InfoRow(
                        label: 'Checklist Completed/Skipped',
                        value:
                            '${_checklistCompletedOrSkipped ? 'Yes' : 'No'} ($_checklistItemsCount items)',
                      ),
                      InfoRow(
                        label: 'Odometer Entered',
                        value: _hasOdometer ? 'Yes' : 'No',
                      ),
                      InfoRow(
                        label: 'Departure Timestamp',
                        value: _departureTimestamp.toIso8601String(),
                      ),
                      if (_missingRequirements.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.xs),
                        for (final item in _missingRequirements)
                          Text(
                            '• $item',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: AppColors.errorRed),
                          ),
                      ],
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SectionCard(
                    title: 'Sync & Connectivity',
                    children: [
                      InfoRow(
                        label: 'Connectivity',
                        value: _isOnline ? 'Online' : 'Offline',
                      ),
                      InfoRow(
                        label: 'Pending Status Sync',
                        value: _pendingStatusCount.toString(),
                      ),
                      InfoRow(
                        label: 'Pending Media Uploads',
                        value: _pendingMediaCount.toString(),
                      ),
                      InfoRow(
                        label: 'Pending Pre-Trip Writes',
                        value: _pendingPreTripCount.toString(),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            await Navigator.push<bool>(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    LiveTrackingPage(tripId: widget.tripId),
                              ),
                            );
                          },
                          icon: const Icon(Icons.map_outlined),
                          label: const Text('Track Location (Live)'),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'You can open live map and Google navigation directly from here.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textMuted,
                        ),
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
