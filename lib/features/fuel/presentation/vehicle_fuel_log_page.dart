import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui_kit/models/enums.dart';
import '../../../ui_kit/theme/app_spacing.dart';
import '../../../ui_kit/widgets/badges.dart';
import '../../../ui_kit/widgets/cards.dart';
import '../../fuel/data/fuel_repository.dart';

class VehicleFuelLogPage extends ConsumerStatefulWidget {
  const VehicleFuelLogPage({super.key});

  @override
  ConsumerState<VehicleFuelLogPage> createState() => _VehicleFuelLogPageState();
}

class _VehicleFuelLogPageState extends ConsumerState<VehicleFuelLogPage> {
  final _vehicleIdCtrl = TextEditingController();
  final _litresCtrl = TextEditingController();
  final _costCtrl = TextEditingController();
  final _odometerCtrl = TextEditingController();
  final _stationCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _fullTank = false;
  bool _submitting = false;
  List<FuelLogSubmission> _recent = const [];

  @override
  void initState() {
    super.initState();
    _loadRecent();
  }

  @override
  void dispose() {
    _vehicleIdCtrl.dispose();
    _litresCtrl.dispose();
    _costCtrl.dispose();
    _odometerCtrl.dispose();
    _stationCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRecent() async {
    final entries = await ref
        .read(fuelRepositoryProvider)
        .recentSubmissions(limit: 10);
    if (!mounted) return;
    setState(() {
      _recent = entries.where((e) => e.scope == 'vehicle').toList();
    });
  }

  Future<void> _submit() async {
    final vehicleId = int.tryParse(_vehicleIdCtrl.text.trim());
    final litres = double.tryParse(_litresCtrl.text.trim());
    final cost = double.tryParse(_costCtrl.text.trim());
    final odometer = double.tryParse(_odometerCtrl.text.trim());

    if (vehicleId == null || vehicleId <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid vehicle ID.')),
      );
      return;
    }
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
    if (odometer == null || odometer <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter valid odometer value (> 0).')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      await ref
          .read(fuelRepositoryProvider)
          .submitVehicleFuelLog(
            vehicleId: vehicleId,
            litres: litres,
            cost: cost,
            odometerKm: odometer,
            fullTank: _fullTank,
            station: _stationCtrl.text.trim(),
            note: _noteCtrl.text.trim(),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vehicle fuel log submitted.')),
      );
      _litresCtrl.clear();
      _costCtrl.clear();
      _odometerCtrl.clear();
      _stationCtrl.clear();
      _noteCtrl.clear();
      setState(() => _fullTank = false);
      await _loadRecent();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Submit failed: $e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Off-Trip Fuel Log')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          SectionCard(
            title: 'Vehicle Fueling',
            children: [
              TextField(
                controller: _vehicleIdCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Vehicle ID *'),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _litresCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Litres *'),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _costCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Cost *'),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _odometerCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Odometer (km) *'),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _stationCtrl,
                decoration: const InputDecoration(labelText: 'Station'),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _noteCtrl,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Note'),
              ),
              const SizedBox(height: AppSpacing.sm),
              SwitchListTile.adaptive(
                value: _fullTank,
                contentPadding: EdgeInsets.zero,
                title: const Text('Full Tank Fill'),
                subtitle: const Text('Mark this fueling as a full-tank event.'),
                onChanged: (v) => setState(() => _fullTank = v),
              ),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _submitting ? null : _submit,
                  icon: _submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_alt_outlined),
                  label: Text(
                    _submitting ? 'Submitting...' : 'Submit Fuel Log',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          SectionCard(
            title: 'Last Submissions',
            children: [
              if (_recent.isEmpty)
                const Text('No submissions yet.')
              else
                ..._recent.map((e) {
                  final status = switch (e.status) {
                    FuelLogSyncStatus.synced => SyncStatus.synced,
                    FuelLogSyncStatus.failed => SyncStatus.failed,
                    FuelLogSyncStatus.queued => SyncStatus.queued,
                  };
                  return InfoRow(
                    label:
                        '${e.recordedAt.toLocal().toString().substring(0, 16)} · ${e.litres.toStringAsFixed(1)}L',
                    valueWidget: SyncStatusBadge(status: status),
                    showDivider: e != _recent.last,
                  );
                }),
            ],
          ),
        ],
      ),
    );
  }
}
