import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../ui_kit/models/enums.dart';
import '../../../ui_kit/theme/app_colors.dart';
import '../../../ui_kit/theme/app_spacing.dart';
import '../../../ui_kit/widgets/badges.dart';
import '../../../ui_kit/widgets/cards.dart';
import '../../../ui_kit/widgets/navigation.dart';
import '../../driver_hub/data/driver_hub_repository.dart';
import '../../fuel/data/fuel_repository.dart';
import '../../maintenance/presentation/maintenance_page.dart';
import '../../notifications/data/notifications_repository.dart';

class DriverHubPage extends ConsumerStatefulWidget {
  const DriverHubPage({super.key, this.initialTab = 0, this.initialDocFilter});

  final int initialTab;
  final String? initialDocFilter;

  @override
  ConsumerState<DriverHubPage> createState() => _DriverHubPageState();
}

class _DriverHubPageState extends ConsumerState<DriverHubPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(
    length: 4,
    vsync: this,
    initialIndex: widget.initialTab.clamp(0, 3),
  );

  DriverProfileData? _profile;
  DriverRank? _rank;
  List<DriverScorePoint> _scores = const [];
  List<DriverBadge> _badges = const [];
  List<ImprovementTip> _tips = const [];
  List<DriverDocumentItem> _documents = const [];
  VehicleInsuranceBlock? _vehicle;
  DriverFuelAnalysis? _fuelAnalysis;
  List<DriverNotification> _timeline = const [];

  bool _loading = true;
  String? _error;
  DateTime? _lastSyncAt;
  bool _stale = false;

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
      final repo = ref.read(driverHubRepositoryProvider);
      final profileLoad = await repo.fetchProfile();
      final rankLoad = await repo.fetchRank();
      final scoresLoad = await repo.fetchScores();
      final badgesLoad = await repo.fetchBadges();
      final tipsLoad = await repo.fetchImprovementTips();
      final docsLoad = await repo.fetchDocuments();
      final vehicleLoad = await repo.fetchAssignedVehicle();
      final timeline = await repo.fetchActivityTimeline();

      DriverFuelAnalysis? analysis;
      final role = await repo.currentRole();
      final canFuel = role == 'admin' ||
          role == 'dispatcher' ||
          role == 'supervisor' ||
          role == 'fleet_manager' ||
          role == 'manager';
      if (canFuel && profileLoad.data.driverId > 0) {
        try {
          analysis = await ref
              .read(fuelRepositoryProvider)
              .fetchDriverAnalysis(driverId: profileLoad.data.driverId);
        } catch (_) {}
      }

      if (!mounted) return;
      final syncCandidates = <DateTime?>[
        profileLoad.lastSyncAt,
        rankLoad.lastSyncAt,
        scoresLoad.lastSyncAt,
        badgesLoad.lastSyncAt,
        tipsLoad.lastSyncAt,
        docsLoad.lastSyncAt,
        vehicleLoad.lastSyncAt,
      ]..removeWhere((e) => e == null);
      final lastSync = syncCandidates.isEmpty
          ? null
          : syncCandidates.cast<DateTime>().reduce(
              (a, b) => a.isAfter(b) ? a : b,
            );

      setState(() {
        _profile = profileLoad.data;
        _rank = rankLoad.data;
        _scores = scoresLoad.data;
        _badges = badgesLoad.data;
        _tips = tipsLoad.data;
        _documents = docsLoad.data;
        _vehicle = vehicleLoad.data;
        _timeline = timeline;
        _fuelAnalysis = analysis;
        _lastSyncAt = lastSync;
        _stale =
            profileLoad.fromCache ||
            rankLoad.fromCache ||
            scoresLoad.fromCache ||
            badgesLoad.fromCache ||
            tipsLoad.fromCache ||
            docsLoad.fromCache ||
            vehicleLoad.fromCache;
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

  String _statusLabel(DriverDocumentStatus status) {
    switch (status) {
      case DriverDocumentStatus.active:
        return 'ACTIVE';
      case DriverDocumentStatus.expiringSoon:
        return 'EXPIRING';
      case DriverDocumentStatus.expired:
        return 'EXPIRED';
      case DriverDocumentStatus.unknown:
        return 'UNKNOWN';
    }
  }

  AlertType _statusAlertType(DriverDocumentStatus status) {
    switch (status) {
      case DriverDocumentStatus.active:
        return AlertType.success;
      case DriverDocumentStatus.expiringSoon:
        return AlertType.warning;
      case DriverDocumentStatus.expired:
        return AlertType.error;
      case DriverDocumentStatus.unknown:
        return AlertType.info;
    }
  }

  Future<void> _uploadDocument() async {
    final typeCtrl = TextEditingController();
    final titleCtrl = TextEditingController();
    final numberCtrl = TextEditingController();
    DateTime? issuedAt;
    DateTime? expiryAt;
    XFile? file;
    final picker = ImagePicker();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setInner) => AlertDialog(
            title: const Text('Upload Document'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: typeCtrl,
                    decoration: const InputDecoration(labelText: 'Type'),
                  ),
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(labelText: 'Title'),
                  ),
                  TextField(
                    controller: numberCtrl,
                    decoration: const InputDecoration(labelText: 'Number'),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          issuedAt == null
                              ? 'Issued: not set'
                              : 'Issued: ${issuedAt!.toLocal().toString().substring(0, 10)}',
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          final now = DateTime.now();
                          final picked = await showDatePicker(
                            context: ctx,
                            firstDate: DateTime(now.year - 20),
                            lastDate: DateTime(now.year + 20),
                            initialDate: issuedAt ?? now,
                          );
                          if (picked != null) setInner(() => issuedAt = picked);
                        },
                        child: const Text('Pick'),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          expiryAt == null
                              ? 'Expiry: required'
                              : 'Expiry: ${expiryAt!.toLocal().toString().substring(0, 10)}',
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          final now = DateTime.now();
                          final picked = await showDatePicker(
                            context: ctx,
                            firstDate: DateTime(now.year - 1),
                            lastDate: DateTime(now.year + 20),
                            initialDate: expiryAt ?? now,
                          );
                          if (picked != null) setInner(() => expiryAt = picked);
                        },
                        child: const Text('Pick'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          file == null ? 'No file selected' : file!.name,
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          final picked = await picker.pickImage(
                            source: ImageSource.camera,
                            imageQuality: 85,
                          );
                          if (picked != null) setInner(() => file = picked);
                        },
                        child: const Text('Capture'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Upload'),
              ),
            ],
          ),
        );
      },
    );

    if (ok != true) return;
    if (typeCtrl.text.trim().isEmpty ||
        titleCtrl.text.trim().isEmpty ||
        expiryAt == null ||
        file == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Type, title, expiry date and file are required.'),
        ),
      );
      return;
    }
    try {
      await ref
          .read(driverHubRepositoryProvider)
          .uploadMyDocument(
            type: typeCtrl.text.trim(),
            title: titleCtrl.text.trim(),
            expiryDate: expiryAt!,
            issuedDate: issuedAt,
            number: numberCtrl.text.trim(),
            file: file!,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Document submitted (or queued offline).'),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ConsMasAppBar(
        title: 'Driver Hub',
        subtitle: 'Performance, compliance and vehicle awareness',
        actions: [
          IconButton(
            icon: const Icon(Icons.build_circle_outlined, color: Colors.white),
            tooltip: 'Maintenance',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MaintenancePage()),
              );
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: AppSpacing.sm),
                    ElevatedButton(
                      onPressed: _load,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          : Column(
              children: [
                if (_stale)
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    child: AlertBanner(
                      type: AlertType.warning,
                      message:
                          'Showing cached data. Last sync: ${_lastSyncAt?.toLocal().toString() ?? 'unknown'}',
                    ),
                  ),
                Container(
                  color: Colors.white,
                  child: TabBar(
                    controller: _tabController,
                    tabs: const [
                      Tab(text: 'My Performance'),
                      Tab(text: 'My Documents'),
                      Tab(text: 'My Compliance'),
                      Tab(text: 'My Vehicle'),
                    ],
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _load,
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _PerformanceTab(
                          profile: _profile!,
                          rank: _rank,
                          badges: _badges,
                          scores: _scores,
                          tips: _tips,
                          fuelAnalysis: _fuelAnalysis,
                        ),
                        _DocumentsTab(
                          documents: _documents,
                          initialFilter: widget.initialDocFilter,
                          statusLabel: _statusLabel,
                          statusAlertType: _statusAlertType,
                          onUpload: _uploadDocument,
                        ),
                        _ComplianceTab(documents: _documents),
                        _VehicleTab(vehicle: _vehicle),
                      ],
                    ),
                  ),
                ),
                _TimelineStrip(items: _timeline),
              ],
            ),
    );
  }
}

class _PerformanceTab extends StatelessWidget {
  const _PerformanceTab({
    required this.profile,
    required this.rank,
    required this.badges,
    required this.scores,
    required this.tips,
    required this.fuelAnalysis,
  });

  final DriverProfileData profile;
  final DriverRank? rank;
  final List<DriverBadge> badges;
  final List<DriverScorePoint> scores;
  final List<ImprovementTip> tips;
  final DriverFuelAnalysis? fuelAnalysis;

  Color _trendColor(String trend) {
    final t = trend.toLowerCase();
    if (t == 'improving') return AppColors.successGreen;
    if (t == 'declining') return AppColors.errorRed;
    return AppColors.accentOrangeDark;
  }

  @override
  Widget build(BuildContext context) {
    final latest = scores.isNotEmpty ? scores.last : null;
    final lowDims = profile.dimensions.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    final dims = [
      'safety',
      'efficiency',
      'compliance',
      'timeliness',
      'professionalism',
    ];

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        SectionCard(
          title: 'Score Cockpit',
          onTap: () {
            showModalBottomSheet<void>(
              context: context,
              builder: (_) => _ScoreHistorySheet(scores: scores, dims: dims),
            );
          },
          children: [
            InfoRow(
              label: 'Overall score',
              value: profile.overallScore.toStringAsFixed(1),
            ),
            InfoRow(label: 'Tier', value: profile.tier.toUpperCase()),
            InfoRow(
              label: 'Rank',
              value: rank == null ? '—' : '${rank!.rank}/${rank!.fleetSize}',
            ),
            InfoRow(
              label: 'Trend',
              valueWidget: Text(
                profile.trend,
                style: TextStyle(
                  color: _trendColor(profile.trend),
                  fontWeight: FontWeight.w700,
                ),
              ),
              showDivider: false,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        SectionCard(
          title: 'Dimension Breakdown',
          children: [
            ...dims.map((d) {
              final value = profile.dimensions[d] ?? latest?.dimensions[d] ?? 0;
              final low = lowDims.isNotEmpty && d == lowDims.first.key;
              return InfoRow(
                label: d[0].toUpperCase() + d.substring(1),
                valueWidget: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(value.toStringAsFixed(1)),
                    if (low) ...[
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () {
                          final matched = tips
                              .where(
                                (t) => t.dimension.toLowerCase().contains(d),
                              )
                              .toList();
                          showModalBottomSheet<void>(
                            context: context,
                            builder: (_) =>
                                _TipsSheet(dimension: d, tips: matched),
                          );
                        },
                        child: const Icon(
                          Icons.tips_and_updates_outlined,
                          size: 18,
                        ),
                      ),
                    ],
                  ],
                ),
                showDivider: d != dims.last,
              );
            }),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        SectionCard(
          title: 'Badge Highlights',
          children: [
            if (badges.isEmpty)
              const Text('No badges yet.')
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: badges.take(6).map((b) {
                  return ActionChip(
                    label: Text(b.title),
                    onPressed: () {
                      showDialog<void>(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: Text(b.title),
                          content: Text(b.description),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Close'),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                }).toList(),
              ),
          ],
        ),
        if (fuelAnalysis != null) ...[
          const SizedBox(height: AppSpacing.md),
          SectionCard(
            title: 'Behavior Indicators',
            children: [
              InfoRow(
                label: 'Fuel efficiency',
                value:
                    fuelAnalysis!.averageKmPerLitre?.toStringAsFixed(2) ?? '—',
              ),
              InfoRow(
                label: 'Litres trend',
                value: fuelAnalysis!.totalLitres?.toStringAsFixed(1) ?? '—',
              ),
              InfoRow(
                label: 'Cost trend',
                value: fuelAnalysis!.totalCost?.toStringAsFixed(1) ?? '—',
                showDivider: false,
              ),
            ],
          ),
        ],
        const SizedBox(height: 64),
      ],
    );
  }
}

class _DocumentsTab extends StatelessWidget {
  const _DocumentsTab({
    required this.documents,
    required this.initialFilter,
    required this.statusLabel,
    required this.statusAlertType,
    required this.onUpload,
  });

  final List<DriverDocumentItem> documents;
  final String? initialFilter;
  final String Function(DriverDocumentStatus) statusLabel;
  final AlertType Function(DriverDocumentStatus) statusAlertType;
  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) {
    final expired = documents
        .where((d) => d.status == DriverDocumentStatus.expired)
        .toList();
    final filtered = (initialFilter == null || initialFilter!.isEmpty)
        ? documents
        : documents
              .where(
                (d) =>
                    d.type.toLowerCase().contains(
                      initialFilter!.toLowerCase(),
                    ) ||
                    d.title.toLowerCase().contains(
                      initialFilter!.toLowerCase(),
                    ),
              )
              .toList();

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        if (expired.isNotEmpty)
          AlertBanner(
            type: AlertType.error,
            message:
                '${expired.length} document(s) expired. Renew immediately.',
          ),
        if (expired.isNotEmpty) const SizedBox(height: AppSpacing.md),
        SectionCard(
          title: 'My Documents',
          trailing: IconButton(
            icon: const Icon(Icons.upload_file_outlined),
            onPressed: onUpload,
          ),
          children: [
            if (filtered.isEmpty)
              const Text('No documents found.')
            else
              ...filtered.map((d) {
                return Column(
                  children: [
                    InfoRow(
                      label: d.type,
                      value:
                          '${d.title}${d.number == null ? '' : ' · ${d.number}'}',
                    ),
                    InfoRow(
                      label: 'Issued',
                      value:
                          d.issuedDate?.toLocal().toString().substring(0, 10) ??
                          '—',
                    ),
                    InfoRow(
                      label: 'Expiry',
                      value:
                          d.expiryDate?.toLocal().toString().substring(0, 10) ??
                          '—',
                    ),
                    InfoRow(
                      label: 'Days',
                      value: d.daysToExpiry?.toString() ?? '—',
                    ),
                    InfoRow(label: 'Status', value: statusLabel(d.status)),
                    InfoRow(
                      label: 'Verification',
                      value: d.verificationStatus.name.toUpperCase(),
                      showDivider: false,
                    ),
                    const SizedBox(height: 6),
                    AlertBanner(
                      type: statusAlertType(d.status),
                      message: d.daysToExpiry == null
                          ? 'No expiry date'
                          : (d.daysToExpiry! < 0
                                ? 'Expired ${d.daysToExpiry!.abs()} day(s) ago'
                                : 'Expires in ${d.daysToExpiry} day(s)'),
                    ),
                    if ((d.documentUrl ?? '').isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () async {
                            final uri = Uri.parse(d.documentUrl!);
                            await launchUrl(
                              uri,
                              mode: LaunchMode.externalApplication,
                            );
                          },
                          icon: const Icon(Icons.open_in_new, size: 18),
                          label: const Text('Preview'),
                        ),
                      ),
                    ],
                    const Divider(height: 20),
                  ],
                );
              }),
          ],
        ),
      ],
    );
  }
}

class _ComplianceTab extends StatelessWidget {
  const _ComplianceTab({required this.documents});
  final List<DriverDocumentItem> documents;

  @override
  Widget build(BuildContext context) {
    final active = documents
        .where((d) => d.status == DriverDocumentStatus.active)
        .length;
    final expiring = documents
        .where((d) => d.status == DriverDocumentStatus.expiringSoon)
        .length;
    final expired = documents
        .where((d) => d.status == DriverDocumentStatus.expired)
        .length;
    final unverified = documents
        .where(
          (d) => d.verificationStatus == DriverVerificationStatus.unverified,
        )
        .length;
    final rejected = documents
        .where((d) => d.verificationStatus == DriverVerificationStatus.rejected)
        .length;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        SectionCard(
          title: 'Compliance Summary',
          children: [
            InfoRow(label: 'Active docs', value: '$active'),
            InfoRow(label: 'Expiring soon', value: '$expiring'),
            InfoRow(label: 'Expired', value: '$expired'),
            InfoRow(
              label: 'Unverified',
              value: '$unverified',
              showDivider: false,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        SectionCard(
          title: 'Compliance Tasks',
          children: [
            CheckboxListTile(
              value: expired == 0,
              onChanged: null,
              title: const Text('Renew expired documents'),
              subtitle: Text(expired == 0 ? 'Done' : '$expired pending'),
            ),
            CheckboxListTile(
              value: unverified == 0,
              onChanged: null,
              title: const Text('Submit missing/unverified documents'),
              subtitle: Text(unverified == 0 ? 'Done' : '$unverified pending'),
            ),
            CheckboxListTile(
              value: rejected == 0,
              onChanged: null,
              title: const Text('Resolve rejected documents'),
              subtitle: Text(rejected == 0 ? 'Done' : '$rejected pending'),
            ),
          ],
        ),
      ],
    );
  }
}

class _VehicleTab extends StatelessWidget {
  const _VehicleTab({required this.vehicle});
  final VehicleInsuranceBlock? vehicle;

  @override
  Widget build(BuildContext context) {
    if (vehicle == null) {
      return ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: const [Text('No assigned vehicle found.')],
      );
    }
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        if (vehicle!.isExpired)
          const AlertBanner(
            type: AlertType.error,
            message: 'Vehicle insurance has expired.',
          )
        else if (vehicle!.isExpiringSoon)
          const AlertBanner(
            type: AlertType.warning,
            message: 'Vehicle insurance is expiring soon.',
          ),
        if (vehicle!.isExpired || vehicle!.isExpiringSoon)
          const SizedBox(height: AppSpacing.md),
        SectionCard(
          title: 'Assigned Vehicle',
          children: [
            InfoRow(label: 'Name', value: vehicle!.vehicleName),
            InfoRow(label: 'Plate', value: vehicle!.plate),
            InfoRow(
              label: 'Type',
              value: vehicle!.vehicleType,
              showDivider: false,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        SectionCard(
          title: 'Insurance',
          children: [
            InfoRow(label: 'Provider', value: vehicle!.provider ?? '—'),
            InfoRow(label: 'Policy #', value: vehicle!.policyNumber ?? '—'),
            InfoRow(
              label: 'Issued',
              value:
                  vehicle!.issuedDate?.toLocal().toString().substring(0, 10) ??
                  '—',
            ),
            InfoRow(
              label: 'Expiry',
              value:
                  vehicle!.expiryDate?.toLocal().toString().substring(0, 10) ??
                  '—',
            ),
            InfoRow(label: 'Coverage', value: vehicle!.coverageAmount ?? '—'),
            InfoRow(
              label: 'Notes',
              value: vehicle!.notes ?? '—',
              showDivider: false,
            ),
            if ((vehicle!.documentUrl ?? '').isNotEmpty)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () async {
                    final uri = Uri.parse(vehicle!.documentUrl!);
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  },
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Open Insurance Document'),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _ScoreHistorySheet extends StatelessWidget {
  const _ScoreHistorySheet({required this.scores, required this.dims});
  final List<DriverScorePoint> scores;
  final List<String> dims;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Score History',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 180,
            child: _LineChart(
              points: scores.map((e) => e.overall).toList(),
              color: AppColors.primaryBlue,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          ...dims.map((d) {
            final series = scores.map((e) => e.dimensions[d] ?? 0).toList();
            final last = series.isNotEmpty ? series.last : 0;
            final prev = series.length > 1 ? series[series.length - 2] : last;
            final improving = last > prev;
            final color = improving
                ? AppColors.successGreen
                : ((last < 50 && !improving)
                      ? AppColors.errorRed
                      : AppColors.accentOrangeDark);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(width: 120, child: Text(d)),
                  Expanded(
                    child: SizedBox(
                      height: 28,
                      child: _LineChart(
                        points: series,
                        color: color,
                        strokeWidth: 2,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _TipsSheet extends StatelessWidget {
  const _TipsSheet({required this.dimension, required this.tips});
  final String dimension;
  final List<ImprovementTip> tips;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Improvement Tips: $dimension',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (tips.isEmpty)
            const Text('No focused tips available yet.')
          else
            ...tips.map(
              (t) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(t.body),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TimelineStrip extends StatelessWidget {
  const _TimelineStrip({required this.items});
  final List<DriverNotification> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Container(
      constraints: const BoxConstraints(maxHeight: 120),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.neutral200)),
      ),
      child: ListView.separated(
        itemCount: math.min(items.length, 6),
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final n = items[index];
          return ListTile(
            dense: true,
            title: Text(n.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              n.body,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Text(
              n.createdAt.toLocal().toString().substring(5, 16),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          );
        },
      ),
    );
  }
}

class _LineChart extends StatelessWidget {
  const _LineChart({
    required this.points,
    required this.color,
    this.strokeWidth = 3,
  });
  final List<double> points;
  final Color color;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _LineChartPainter(
        points: points,
        color: color,
        strokeWidth: strokeWidth,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  _LineChartPainter({
    required this.points,
    required this.color,
    required this.strokeWidth,
  });
  final List<double> points;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()
      ..color = AppColors.neutral100
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bg);
    if (points.length < 2) return;

    final minVal = points.reduce(math.min);
    final maxVal = points.reduce(math.max);
    final range = (maxVal - minVal).abs() < 0.01 ? 1.0 : (maxVal - minVal);

    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final x = (i / (points.length - 1)) * size.width;
      final y = size.height - ((points[i] - minVal) / range) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
