import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui_kit/models/enums.dart';
import '../../../ui_kit/theme/app_spacing.dart';
import '../../../ui_kit/widgets/badges.dart';
import '../../../ui_kit/widgets/buttons.dart';
import '../../../ui_kit/widgets/cards.dart';
import '../../chat/presentation/trip_chat_page.dart';
import '../../driver_hub/data/driver_hub_repository.dart';
import '../../driver_hub/presentation/driver_hub_page.dart';
import '../../incidents/presentation/incidents_page.dart';
import '../../notifications/data/notifications_repository.dart';
import '../../notifications/presentation/notifications_inbox_page.dart';
import '../../trips/data/trips_repository.dart';
import '../../trips/domain/trip.dart';
import '../../trips/presentation/trip_detail_page.dart';

class DriverHomePage extends ConsumerStatefulWidget {
  const DriverHomePage({super.key});

  @override
  ConsumerState<DriverHomePage> createState() => _DriverHomePageState();
}

class _DriverHomePageState extends ConsumerState<DriverHomePage> {
  bool _loading = true;
  String? _error;
  Trip? _activeTrip;
  List<DriverDocumentItem> _documents = const [];
  Map<String, dynamic>? _complianceResult;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final trips = await ref.read(tripsRepositoryProvider).fetchAssignedTrips();
      final docs = await ref.read(driverHubRepositoryProvider).fetchDocuments();
      final active = trips.where((t) {
        return {
          'assigned',
          'loaded',
          'en_route',
          'arrived',
          'offloaded',
        }.contains(t.status);
      }).toList();
      if (!mounted) return;
      setState(() {
        _activeTrip = active.isEmpty ? null : active.first;
        _documents = docs.data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _runReadinessCheck() async {
    final trip = _activeTrip;
    if (trip == null) return;
    try {
      final result = await ref
          .read(tripsRepositoryProvider)
          .verifyTripCompliance(trip.id);
      if (!mounted) return;
      setState(() => _complianceResult = result);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Readiness check failed: $e')),
      );
    }
  }

  int get _expiredDocs =>
      _documents.where((d) => d.status == DriverDocumentStatus.expired).length;
  int get _expiringDocs =>
      _documents.where((d) => d.status == DriverDocumentStatus.expiringSoon).length;

  @override
  Widget build(BuildContext context) {
    final unreadAsync = ref.watch(notificationsUnreadCountProvider);
    final unreadCount = unreadAsync.maybeWhen(data: (v) => v, orElse: () => 0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        actions: [
          IconButton(
            icon: Badge(
              isLabelVisible: unreadCount > 0,
              label: Text('$unreadCount'),
              child: const Icon(Icons.notifications_none),
            ),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NotificationsInboxPage()),
              );
              if (!mounted) return;
              ref.invalidate(notificationsUnreadCountProvider);
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text('Failed to load home: $_error'))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  SectionCard(
                    title: 'Active Trip',
                    children: [
                      if (_activeTrip == null) const Text('No active trip')
                      else ...[
                        InfoRow(
                          label: 'Reference',
                          value: _activeTrip!.referenceCode,
                        ),
                        InfoRow(
                          label: 'Status',
                          value: _activeTrip!.status,
                        ),
                        InfoRow(
                          label: 'Destination',
                          value: _activeTrip!.destination ??
                              _activeTrip!.deliveryAddress ??
                              '—',
                          showDivider: false,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        AppSecondaryButton(
                          label: 'Open Trip',
                          leadingIcon: Icons.local_shipping_outlined,
                          onPressed: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => TripDetailPage(tripId: _activeTrip!.id),
                              ),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SectionCard(
                    title: 'Compliance Readiness',
                    children: [
                      if (_activeTrip == null)
                        const Text('No trip selected for readiness check.')
                      else ...[
                        if (_complianceResult != null)
                          AlertBanner(
                            type: (_isBlocked(_complianceResult!))
                                ? AlertType.error
                                : (_warnings(_complianceResult!) > 0
                                      ? AlertType.warning
                                      : AlertType.success),
                            message: _readinessMessage(_complianceResult!),
                          ),
                        const SizedBox(height: AppSpacing.sm),
                        AppSecondaryButton(
                          label: 'Run readiness check',
                          leadingIcon: Icons.verified_user_outlined,
                          onPressed: _runReadinessCheck,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SectionCard(
                    title: 'Document Status',
                    children: [
                      InfoRow(label: 'Expired', value: '$_expiredDocs'),
                      InfoRow(label: 'Expiring soon', value: '$_expiringDocs'),
                      InfoRow(
                        label: 'Total',
                        value: '${_documents.length}',
                        showDivider: false,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SectionCard(
                    title: 'Quick Actions',
                    children: [
                      AppSecondaryButton(
                        label: 'Start Compliance Check',
                        leadingIcon: Icons.fact_check_outlined,
                        onPressed: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const DriverHubPage(initialTab: 2),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      AppSecondaryButton(
                        label: 'Report Incident',
                        leadingIcon: Icons.warning_amber_outlined,
                        onPressed: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => IncidentsPage(
                                initialTripId: _activeTrip?.id,
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      AppSecondaryButton(
                        label: 'Upload Document',
                        leadingIcon: Icons.file_upload_outlined,
                        onPressed: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const DriverHubPage(initialTab: 1),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      AppSecondaryButton(
                        label: 'Open Trip Chat',
                        leadingIcon: Icons.chat_bubble_outline,
                        onPressed: _activeTrip == null
                            ? null
                            : () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => TripChatPage(
                                      tripId: _activeTrip!.id,
                                      tripReference: _activeTrip!.referenceCode,
                                      tripStatus: _activeTrip!.status,
                                    ),
                                  ),
                                );
                              },
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  bool _isBlocked(Map<String, dynamic> data) {
    final blocked = data['blocked'];
    if (blocked is bool) return blocked;
    final failures = data['blocking_failures'] ?? data['failures'];
    return failures is List && failures.isNotEmpty;
  }

  int _warnings(Map<String, dynamic> data) {
    final warnings = data['warnings'];
    if (warnings is List) return warnings.length;
    return 0;
  }

  String _readinessMessage(Map<String, dynamic> data) {
    if (_isBlocked(data)) {
      return 'Not ready. Resolve blocking compliance items before departure.';
    }
    final warningCount = _warnings(data);
    if (warningCount > 0) {
      return 'Ready with warnings ($warningCount). Review before departure.';
    }
    return 'Ready for departure.';
  }
}
