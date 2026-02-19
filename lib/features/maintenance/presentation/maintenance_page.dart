import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui_kit/models/enums.dart';
import '../../../ui_kit/theme/app_colors.dart';
import '../../../ui_kit/theme/app_spacing.dart';
import '../../../ui_kit/widgets/badges.dart';
import '../../../ui_kit/widgets/cards.dart';
import '../../../ui_kit/widgets/navigation.dart';
import '../../maintenance/data/maintenance_repository.dart';

class MaintenancePage extends ConsumerStatefulWidget {
  const MaintenancePage({super.key});

  @override
  ConsumerState<MaintenancePage> createState() => _MaintenancePageState();
}

class _MaintenancePageState extends ConsumerState<MaintenancePage> {
  bool _loading = true;
  String? _error;
  String? _warning;
  MaintenanceSnapshot? _snapshot;
  final Map<int, bool> _commenting = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final result = await ref
          .read(maintenanceRepositoryProvider)
          .fetchSnapshot();
      if (!mounted) return;
      setState(() {
        _snapshot = result.snapshot;
        _warning = result.warning;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _dateLabel(DateTime? date) {
    if (date == null) return '—';
    final d = date.toLocal();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  String _docCountdown(DateTime? expiry) {
    if (expiry == null) return 'No expiry date';
    final now = DateTime.now();
    final d = DateTime(
      expiry.year,
      expiry.month,
      expiry.day,
    ).difference(DateTime(now.year, now.month, now.day)).inDays;
    if (d < 0) return 'Expired ${d.abs()} day(s) ago';
    if (d == 0) return 'Expires today';
    return 'Expires in $d day(s)';
  }

  AlertType _docAlertType(VehicleDocumentStatus status) {
    switch (status) {
      case VehicleDocumentStatus.expired:
        return AlertType.error;
      case VehicleDocumentStatus.expiring:
        return AlertType.warning;
      case VehicleDocumentStatus.active:
        return AlertType.success;
      case VehicleDocumentStatus.unknown:
        return AlertType.info;
    }
  }

  Color _woStatusColor(String status) {
    final v = status.toLowerCase();
    if (v == 'completed' || v == 'closed') return AppColors.successGreen;
    if (v == 'in_progress' || v == 'ongoing') return AppColors.primaryBlue;
    if (v == 'cancelled' || v == 'blocked') return AppColors.errorRed;
    return AppColors.accentOrangeDark;
  }

  Future<void> _addComment(WorkOrder wo) async {
    final ctrl = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Comment on ${wo.number}'),
        content: TextField(
          controller: ctrl,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Add your update for maintenance team...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (text == null || text.isEmpty) return;
    setState(() => _commenting[wo.id] = true);
    try {
      await ref
          .read(maintenanceRepositoryProvider)
          .addWorkOrderComment(workOrderId: wo.id, comment: text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Comment added to work order.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to add comment: $e')));
    } finally {
      if (mounted) {
        setState(() => _commenting.remove(wo.id));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final docs = snapshot?.documents ?? const <VehicleDocument>[];
    final expiredCount = docs
        .where((d) => d.status == VehicleDocumentStatus.expired)
        .length;
    final expiringCount = docs
        .where((d) => d.status == VehicleDocumentStatus.expiring)
        .length;

    return Scaffold(
      appBar: const ConsMasAppBar(
        title: 'Maintenance',
        subtitle: 'Driver maintenance awareness',
      ),
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
            Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    ElevatedButton(
                      onPressed: _load,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          else
            RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  if (_warning != null) ...[
                    AlertBanner(type: AlertType.warning, message: _warning!),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  if (snapshot != null && snapshot.alerts.isNotEmpty) ...[
                    for (final alert in snapshot.alerts) ...[
                      AlertBanner(
                        type: alert.type.contains('overdue')
                            ? AlertType.error
                            : AlertType.warning,
                        message: alert.message,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  if (expiredCount > 0) ...[
                    AlertBanner(
                      type: AlertType.error,
                      message:
                          '$expiredCount vehicle document(s) expired. Renew immediately.',
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  if (expiringCount > 0) ...[
                    AlertBanner(
                      type: AlertType.warning,
                      message:
                          '$expiringCount vehicle document(s) expiring soon.',
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  SectionCard(
                    title: 'My Vehicle Status',
                    accentColor: snapshot?.status.isOverdue == true
                        ? AppColors.errorRed
                        : AppColors.primaryBlue,
                    children: [
                      InfoRow(
                        label: 'Next due',
                        value: _dateLabel(snapshot?.status.nextDueMaintenance),
                      ),
                      InfoRow(
                        label: 'Service',
                        value: snapshot?.status.nextServiceLabel ?? '—',
                      ),
                      InfoRow(
                        label: 'Days to due',
                        value: snapshot?.status.daysToDue?.toString() ?? '—',
                      ),
                      InfoRow(
                        label: 'KM to due',
                        value: snapshot?.status.kmToDue == null
                            ? '—'
                            : '${snapshot!.status.kmToDue!.toStringAsFixed(0)} km',
                      ),
                      InfoRow(
                        label: 'Current ODO',
                        value: snapshot?.status.currentOdometerKm == null
                            ? '—'
                            : '${snapshot!.status.currentOdometerKm!.toStringAsFixed(0)} km',
                        showDivider: false,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      if (snapshot?.status.isOverdue == true)
                        const AlertBanner(
                          type: AlertType.error,
                          message: 'Maintenance overdue for this vehicle.',
                        )
                      else if (snapshot?.status.isDueSoon == true)
                        const AlertBanner(
                          type: AlertType.warning,
                          message:
                              'Maintenance due soon. Plan service with dispatcher.',
                        )
                      else
                        const AlertBanner(
                          type: AlertType.success,
                          message: 'Vehicle maintenance status is healthy.',
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SectionCard(
                    title: 'My Vehicle Documents',
                    children: [
                      if (docs.isEmpty)
                        const Text('No vehicle documents found.')
                      else
                        for (var i = 0; i < docs.length; i++) ...[
                          InfoRow(
                            label: docs[i].type,
                            valueWidget: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Flexible(
                                  child: Text(
                                    _dateLabel(docs[i].expiryDate),
                                    textAlign: TextAlign.right,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium
                                        ?.copyWith(
                                          color: AppColors.textPrimary,
                                        ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _StatusBadge(status: docs[i].status),
                              ],
                            ),
                            showDivider: i != docs.length - 1,
                          ),
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppSpacing.sm,
                            ),
                            child: AlertBanner(
                              type: _docAlertType(docs[i].status),
                              message: _docCountdown(docs[i].expiryDate),
                            ),
                          ),
                        ],
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SectionCard(
                    title: 'Work Orders for My Vehicle',
                    children: [
                      if (snapshot == null || snapshot.workOrders.isEmpty)
                        const Text('No work orders found.')
                      else
                        ...snapshot.workOrders.map((wo) {
                          final color = _woStatusColor(wo.status);
                          final canComment =
                              snapshot.allowWorkOrderComments || wo.canComment;
                          return Container(
                            margin: const EdgeInsets.only(
                              bottom: AppSpacing.sm,
                            ),
                            padding: const EdgeInsets.all(AppSpacing.md),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.neutral200),
                              color: AppColors.surface,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${wo.number} · ${wo.title}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: color.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                      child: Text(
                                        wo.status.toUpperCase(),
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(color: color),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Scheduled: ${_dateLabel(wo.scheduledDate)}',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: AppColors.textMuted),
                                ),
                                if ((wo.notes ?? '').trim().isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    wo.notes!,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyMedium,
                                  ),
                                ],
                                const SizedBox(height: 8),
                                if (canComment)
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton.icon(
                                      onPressed: _commenting[wo.id] == true
                                          ? null
                                          : () => _addComment(wo),
                                      icon: _commenting[wo.id] == true
                                          ? const SizedBox(
                                              width: 14,
                                              height: 14,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Icon(Icons.comment_outlined),
                                      label: const Text('Add Comment'),
                                    ),
                                  )
                                else
                                  Text(
                                    'Read-only',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(color: AppColors.textMuted),
                                  ),
                              ],
                            ),
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

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final VehicleDocumentStatus status;

  @override
  Widget build(BuildContext context) {
    late final Color fg;
    late final Color bg;
    late final String text;
    switch (status) {
      case VehicleDocumentStatus.active:
        fg = AppColors.successGreenDark;
        bg = AppColors.successGreenLight;
        text = 'ACTIVE';
        break;
      case VehicleDocumentStatus.expiring:
        fg = AppColors.accentOrangeDark;
        bg = AppColors.accentOrangeLight;
        text = 'EXPIRING';
        break;
      case VehicleDocumentStatus.expired:
        fg = AppColors.errorRed;
        bg = AppColors.errorRedLight;
        text = 'EXPIRED';
        break;
      case VehicleDocumentStatus.unknown:
        fg = AppColors.textMuted;
        bg = AppColors.neutral100;
        text = 'UNKNOWN';
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: fg,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
