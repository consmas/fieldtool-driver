import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/token_storage.dart';
import '../../../ui_kit/models/enums.dart';
import '../../../ui_kit/theme/app_spacing.dart';
import '../../../ui_kit/widgets/badges.dart';
import '../../../ui_kit/widgets/cards.dart';
import '../../fuel/data/fuel_repository.dart';

class FuelInsightsPage extends ConsumerStatefulWidget {
  const FuelInsightsPage({super.key});

  @override
  ConsumerState<FuelInsightsPage> createState() => _FuelInsightsPageState();
}

class _FuelInsightsPageState extends ConsumerState<FuelInsightsPage> {
  bool _loading = true;
  String? _error;
  DriverFuelAnalysis? _analysis;

  Future<String?> _roleFromToken() async {
    try {
      final token = await ref.read(tokenStorageProvider).readToken();
      if (token == null || token.isEmpty) return null;
      final parts = token.split('.');
      if (parts.length < 2) return null;
      final payload = utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      );
      final map = jsonDecode(payload) as Map<String, dynamic>;
      final role = map['role']?.toString().toLowerCase();
      if (role != null && role.isNotEmpty) return role;
      final scope = map['scp']?.toString().toLowerCase();
      if (scope == null || scope.isEmpty) return null;
      if (scope == 'admin' ||
          scope == 'dispatcher' ||
          scope == 'supervisor' ||
          scope == 'fleet_manager' ||
          scope == 'manager') {
        return scope;
      }
      return 'user';
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<int?> _driverIdFromToken() async {
    try {
      final token = await ref.read(tokenStorageProvider).readToken();
      if (token == null || token.isEmpty) return null;
      final parts = token.split('.');
      if (parts.length < 2) return null;
      final payload = utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      );
      final map = jsonDecode(payload) as Map<String, dynamic>;
      return int.tryParse(map['sub']?.toString() ?? '');
    } catch (_) {
      return null;
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final role = await _roleFromToken();
      final canAccess = role == 'admin' ||
          role == 'dispatcher' ||
          role == 'supervisor' ||
          role == 'fleet_manager' ||
          role == 'manager';
      if (!canAccess) {
        throw Exception(
          'Fuel analysis is available only to dispatch/fleet roles.',
        );
      }
      final driverId = await _driverIdFromToken();
      if (driverId == null || driverId <= 0) {
        throw Exception('Could not determine driver id.');
      }
      final analysis = await ref
          .read(fuelRepositoryProvider)
          .fetchDriverAnalysis(driverId: driverId);
      if (!mounted) return;
      setState(() {
        _analysis = analysis;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  String _fmt(double? value, {String suffix = ''}) {
    if (value == null) return '—';
    return '${value.toStringAsFixed(2)}$suffix';
  }

  @override
  Widget build(BuildContext context) {
    final a = _analysis;
    return Scaffold(
      appBar: AppBar(title: const Text('Fuel Insights')),
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFF2F7FF), Color(0xFFFFFFFF)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_error != null)
            ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                AlertBanner(type: AlertType.error, message: _error!),
                const SizedBox(height: AppSpacing.md),
                ElevatedButton(onPressed: _load, child: const Text('Retry')),
              ],
            )
          else
            RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  SectionCard(
                    title: 'Efficiency Summary',
                    children: [
                      InfoRow(
                        label: 'Avg km/L',
                        value: _fmt(a?.averageKmPerLitre),
                      ),
                      InfoRow(
                        label: 'Total Litres',
                        value: _fmt(a?.totalLitres, suffix: ' L'),
                      ),
                      InfoRow(label: 'Total Cost', value: _fmt(a?.totalCost)),
                      InfoRow(
                        label: 'Distance',
                        value: _fmt(a?.totalDistanceKm, suffix: ' km'),
                        showDivider: false,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SectionCard(
                    title: 'Trend',
                    children: [
                      if ((a?.monthlyTrend ?? const []).isEmpty)
                        const Text('No trend data available.')
                      else
                        ...(a!.monthlyTrend).map((row) {
                          final label =
                              (row['label'] ??
                                      row['month'] ??
                                      row['period'] ??
                                      'Period')
                                  .toString();
                          final eff =
                              row['km_per_litre'] ??
                              row['efficiency'] ??
                              row['avg_km_per_litre'];
                          return InfoRow(
                            label: label,
                            value: eff == null ? '—' : '${eff.toString()} km/L',
                            showDivider: row != a.monthlyTrend.last,
                          );
                        }),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
